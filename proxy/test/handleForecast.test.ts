import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { handleForecast } from "../src/index";
import { canonicalAppAuthInput, APP_AUTH_TS_WINDOW_SECONDS } from "../src/privacy";
import type { Env, RawForecastEntry, RawForecastResponse } from "../src/types";

const ZERO_SECRET =
  "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"; // 48 zero bytes

const ENC = new TextEncoder();

function makeEntry(time: string): RawForecastEntry {
  return { time, wind_mps: 5, wind_deg: 90, wind_beaufort: 3, gust_mps: 7 };
}

function makeRaw(): RawForecastResponse {
  return {
    model_run: "2026-04-21T06:00:00Z",
    forecasts: [
      makeEntry("2026-04-21T09:00:00Z"),
      makeEntry("2026-04-21T10:00:00Z"),
      makeEntry("2026-04-21T11:00:00Z"),
    ],
  };
}

function makeEnv(secret = ZERO_SECRET, prev?: string): Env {
  // In-memory KV stub, primed with model_run + raw forecast for the cell.
  const raw = makeRaw();
  const store = new Map<string, string>([
    ["latest_model_run", raw.model_run],
  ]);
  const kv = {
    async get(key: string) {
      if (store.has(key)) return store.get(key);
      // Prime any forecast_* key on demand to keep the test path offline.
      if (key.startsWith("forecast_")) {
        store.set(key, JSON.stringify(raw));
        return store.get(key);
      }
      return null;
    },
    async put(key: string, value: string) {
      store.set(key, value);
    },
  } as unknown as KVNamespace;
  return {
    FORECAST_CACHE: kv,
    APP_IDS: ["384eef47-978a-48c0-ad33-31bdfe9ec18f"],
    APP_AUTH_SECRET: secret,
    APP_AUTH_SECRET_PREV: prev,
  };
}

async function rawHmac(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const ck = await crypto.subtle.importKey(
    "raw",
    key as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", ck, data as BufferSource));
}

function bytesToBase64Std(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

function base64UrlEncodeBytes(bytes: Uint8Array): string {
  return bytesToBase64Std(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function deriveRawKeys(secret: string) {
  const ikm = Uint8Array.from(atob(secret), (c) => c.charCodeAt(0));
  const zero32 = new Uint8Array(32);
  const prk = await rawHmac(zero32, ikm);
  const encInfo = new Uint8Array([...ENC.encode("wf-enc-v1"), 0x01]);
  const macInfo = new Uint8Array([...ENC.encode("wf-mac-v1"), 0x01]);
  const authInfo = new Uint8Array([...ENC.encode("wf-auth-v1"), 0x01]);
  const enc = await rawHmac(prk, encInfo);
  const mac = await rawHmac(prk, macInfo);
  const auth = await rawHmac(prk, authInfo);
  return { enc, mac, auth };
}

async function buildEncryptedRequest(opts: {
  secret: string;
  ts: number;
  payloadTs?: number;
  lat?: string;
  lon?: string;
  units?: string;
  slots?: string;
  app?: string;
  appId?: string;
  appVer?: string;
  tamperEnvelope?: boolean;
  iv?: Uint8Array;
}): Promise<{ request: Request; url: URL; q: string }> {
  const lat = opts.lat ?? "53.349";
  const lon = opts.lon ?? "-6.260";
  const units = opts.units ?? "beaufort";
  const slots = opts.slots ?? "0,3,6";
  const payloadTs = opts.payloadTs ?? opts.ts;

  const { enc, mac, auth } = await deriveRawKeys(opts.secret);
  const aesKey = await crypto.subtle.importKey(
    "raw",
    enc as BufferSource,
    { name: "AES-CBC" },
    false,
    ["encrypt"],
  );
  const iv = opts.iv ?? crypto.getRandomValues(new Uint8Array(16));
  const plaintext = `{"lat":"${lat}","lon":"${lon}","units":"${units}","slots":"${slots}","ts":${payloadTs}}`;
  const ctBuf = await crypto.subtle.encrypt(
    { name: "AES-CBC", iv: iv as BufferSource },
    aesKey,
    ENC.encode(plaintext) as BufferSource,
  );
  const ct = new Uint8Array(ctBuf);
  const ivCt = new Uint8Array(iv.length + ct.length);
  ivCt.set(iv, 0);
  ivCt.set(ct, iv.length);
  const envMac = await rawHmac(mac, ivCt);
  let envelope = new Uint8Array(iv.length + ct.length + envMac.length);
  envelope.set(iv, 0);
  envelope.set(ct, iv.length);
  envelope.set(envMac, iv.length + ct.length);
  if (opts.tamperEnvelope) {
    envelope = new Uint8Array(envelope);
    envelope[envelope.length - 1] ^= 0x01;
  }
  const q = base64UrlEncodeBytes(envelope);

  const app = opts.app ?? "Wind Force";
  const appId = opts.appId ?? "384eef47-978a-48c0-ad33-31bdfe9ec18f";
  const appVer = opts.appVer ?? "1.0.0";
  const tsStr = String(opts.ts);
  const canonical = canonicalAppAuthInput("GET", "/v1/forecast", q, tsStr, app, appId, appVer);
  const authMac = await rawHmac(auth, canonical);

  const url = new URL(`https://example.com/v1/forecast?q=${q}`);
  const request = new Request(url.toString(), {
    method: "GET",
    headers: {
      "X-WF-App": app,
      "X-WF-AppID": appId,
      "X-WF-App-Ver": appVer,
      "X-WF-App-Ts": tsStr,
      "X-WF-App-Mac": base64UrlEncodeBytes(authMac),
    },
  });
  return { request, url, q };
}

describe("handleForecast — encrypted path", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(1_776_469_200_000));
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("returns 200 for a valid encrypted request", async () => {
    const ts = Math.floor(Date.now() / 1000);
    const { request, url } = await buildEncryptedRequest({ secret: ZERO_SECRET, ts });
    const res = await handleForecast(request, url, makeEnv());
    expect(res.status).toBe(200);
    const body = (await res.json()) as { units: string; forecasts: unknown[] };
    expect(body.units).toBe("beaufort");
    expect(Array.isArray(body.forecasts)).toBe(true);
  });

  it("returns 400 when the envelope MAC is tampered", async () => {
    const ts = Math.floor(Date.now() / 1000);
    const { request, url } = await buildEncryptedRequest({
      secret: ZERO_SECRET,
      ts,
      tamperEnvelope: true,
    });
    const res = await handleForecast(request, url, makeEnv());
    expect(res.status).toBe(400);
  });

  it("returns 403 when the app-auth MAC was signed with the wrong secret", async () => {
    const ts = Math.floor(Date.now() / 1000);
    // Sign with a secret the server does not accept.
    const wrong = bytesToBase64Std(new Uint8Array(48).fill(7));
    const { request, url } = await buildEncryptedRequest({ secret: wrong, ts });
    const res = await handleForecast(request, url, makeEnv(ZERO_SECRET));
    expect(res.status).toBe(403);
  });

  it("returns 403 when the timestamp is outside the window", async () => {
    const nowS = Math.floor(Date.now() / 1000);
    const ts = nowS + APP_AUTH_TS_WINDOW_SECONDS + 5;
    const { request, url } = await buildEncryptedRequest({ secret: ZERO_SECRET, ts });
    const res = await handleForecast(request, url, makeEnv());
    expect(res.status).toBe(403);
  });

  it("returns 403 when payload ts mismatches header ts", async () => {
    const ts = Math.floor(Date.now() / 1000);
    const { request, url } = await buildEncryptedRequest({
      secret: ZERO_SECRET,
      ts,
      payloadTs: ts - 1, // different
    });
    const res = await handleForecast(request, url, makeEnv());
    expect(res.status).toBe(403);
  });

  it("returns 403 when any X-WF-* header is missing", async () => {
    const ts = Math.floor(Date.now() / 1000);
    const { request, url, q } = await buildEncryptedRequest({ secret: ZERO_SECRET, ts });
    const stripped = new Request(request.url, {
      method: "GET",
      headers: {
        // Drop X-WF-App
        "X-WF-AppID": request.headers.get("X-WF-AppID")!,
        "X-WF-App-Ver": request.headers.get("X-WF-App-Ver")!,
        "X-WF-App-Ts": request.headers.get("X-WF-App-Ts")!,
        "X-WF-App-Mac": request.headers.get("X-WF-App-Mac")!,
      },
    });
    void q;
    const res = await handleForecast(stripped, url, makeEnv());
    expect(res.status).toBe(403);
  });

  it("succeeds under APP_AUTH_SECRET_PREV during a grace window", async () => {
    const ts = Math.floor(Date.now() / 1000);
    const prev = ZERO_SECRET;
    const active = bytesToBase64Std(new Uint8Array(48).fill(0x42));
    const { request, url } = await buildEncryptedRequest({ secret: prev, ts });
    const res = await handleForecast(request, url, makeEnv(active, prev));
    expect(res.status).toBe(200);
  });

  it("rejects a mixed-mode request that carries both q and lat", async () => {
    const ts = Math.floor(Date.now() / 1000);
    const { request, url, q } = await buildEncryptedRequest({ secret: ZERO_SECRET, ts });
    const mixedUrl = new URL(`https://example.com/v1/forecast?q=${q}&lat=53.349&lon=-6.260`);
    const res = await handleForecast(request, mixedUrl, makeEnv());
    expect(res.status).toBe(400);
  });
});

describe("handleForecast — legacy plaintext path", () => {
  it("still serves a valid plaintext request with no X-WF-* headers", async () => {
    const url = new URL("https://example.com/v1/forecast?lat=53.349&lon=-6.260");
    const request = new Request(url.toString(), { method: "GET" });
    const res = await handleForecast(request, url, makeEnv());
    expect(res.status).toBe(200);
  });

  it("returns 400 when lat/lon are missing", async () => {
    const url = new URL("https://example.com/v1/forecast");
    const request = new Request(url.toString(), { method: "GET" });
    const res = await handleForecast(request, url, makeEnv());
    expect(res.status).toBe(400);
  });
});
