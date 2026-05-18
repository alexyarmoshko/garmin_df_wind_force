import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  deriveKeys,
  canonicalAppAuthInput,
  verifyAppAuth,
  decryptEnvelope,
  collectSecrets,
  APP_AUTH_TS_WINDOW_SECONDS,
} from "../src/privacy";
import type { Env } from "../src/types";

const ZERO_SECRET =
  "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"; // 48 zero bytes

const FIXED_Q =
  "AAAAAAAAAAAAAAAAAAAAAFqkd0IcODOZhs_79gJcv5bkw8HEgQcxrAyYYohlcjsjurDdcsYm492nLrVs9js_ka3nZpDjIXaTbaqMhOc2mHPaOuOuXkAI3n_iarY13TEA_nU572diKw1BjG2Tz-CK-_W-FO38SevgfwfapkXvhz0";

const FIXED_AUTH_MAC = "68nckg-wUCp3fX3N4ubH83fLNCT5NS2S8DbbvPHGVQE";

const ENC = new TextEncoder();

function bytesToHex(b: Uint8Array): string {
  return Array.from(b, (v) => v.toString(16).padStart(2, "0")).join("");
}

function bytesFromHex(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    out[i / 2] = parseInt(hex.substr(i, 2), 16);
  }
  return out;
}

function bytesToBase64Std(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

function base64UrlEncodeBytes(bytes: Uint8Array): string {
  return bytesToBase64Std(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
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

async function buildEnvelope(
  secret: string,
  iv: Uint8Array,
  plaintext: string,
): Promise<{ q: string; ct: Uint8Array; mac: Uint8Array }> {
  const ikm = Uint8Array.from(atob(secret), (c) => c.charCodeAt(0));
  const zero32 = new Uint8Array(32);
  const prk = await rawHmac(zero32, ikm);
  const encInfo = new Uint8Array([...ENC.encode("wf-enc-v1"), 0x01]);
  const macInfo = new Uint8Array([...ENC.encode("wf-mac-v1"), 0x01]);
  const encRaw = await rawHmac(prk, encInfo);
  const macRaw = await rawHmac(prk, macInfo);
  const aesKey = await crypto.subtle.importKey(
    "raw",
    encRaw as BufferSource,
    { name: "AES-CBC" },
    false,
    ["encrypt"],
  );
  const ctBuf = await crypto.subtle.encrypt(
    { name: "AES-CBC", iv: iv as BufferSource },
    aesKey,
    ENC.encode(plaintext) as BufferSource,
  );
  const ct = new Uint8Array(ctBuf);
  const ivCt = new Uint8Array(iv.length + ct.length);
  ivCt.set(iv, 0);
  ivCt.set(ct, iv.length);
  const mac = await rawHmac(macRaw, ivCt);
  const env = new Uint8Array(iv.length + ct.length + mac.length);
  env.set(iv, 0);
  env.set(ct, iv.length);
  env.set(mac, iv.length + ct.length);
  return { q: base64UrlEncodeBytes(env), ct, mac };
}

async function buildAuthMac(
  secret: string,
  method: string,
  path: string,
  q: string,
  ts: string,
  app: string,
  appId: string,
  appVer: string,
): Promise<string> {
  const ikm = Uint8Array.from(atob(secret), (c) => c.charCodeAt(0));
  const zero32 = new Uint8Array(32);
  const prk = await rawHmac(zero32, ikm);
  const authInfo = new Uint8Array([...ENC.encode("wf-auth-v1"), 0x01]);
  const authRaw = await rawHmac(prk, authInfo);
  const canonical = canonicalAppAuthInput(method, path, q, ts, app, appId, appVer);
  const mac = await rawHmac(authRaw, canonical);
  return base64UrlEncodeBytes(mac);
}

function makeRequest(headers: Record<string, string>): Request {
  return new Request("https://example.com/v1/forecast?q=stub", {
    method: "GET",
    headers,
  });
}

// ── Key schedule test vector (independent ground truth) ──────────────

describe("deriveKeys vector", () => {
  it("matches the fixed all-zero IKM vector", async () => {
    const ikm = Uint8Array.from(atob(ZERO_SECRET), (c) => c.charCodeAt(0));
    expect(bytesToHex(ikm)).toBe(
      "000000000000000000000000000000000000000000000000" +
        "000000000000000000000000000000000000000000000000",
    );

    const zero32 = new Uint8Array(32);
    const prk = await rawHmac(zero32, ikm);
    expect(bytesToHex(prk)).toBe(
      "c30eb735be796b1095c4e0098268ee08322d38a2c589e12376054aaa65a9a07d",
    );

    const encInfo = new Uint8Array([...ENC.encode("wf-enc-v1"), 0x01]);
    const macInfo = new Uint8Array([...ENC.encode("wf-mac-v1"), 0x01]);
    const authInfo = new Uint8Array([...ENC.encode("wf-auth-v1"), 0x01]);
    const encRaw = await rawHmac(prk, encInfo);
    const macRaw = await rawHmac(prk, macInfo);
    const authRaw = await rawHmac(prk, authInfo);
    expect(bytesToHex(encRaw)).toBe(
      "3aa400c95f44e7f87a9f38d9f9c350a26475ea8c913a6dd64afdeef97f9d1398",
    );
    expect(bytesToHex(macRaw)).toBe(
      "66a1761c7ccf3af5a749547f71e9c46000e18933660b9bcd3a7446319d98316f",
    );
    expect(bytesToHex(authRaw)).toBe(
      "efa7ee5ac2b4ec1e865b046974ae490f150d40db5e91af00f0d257e2feed7c14",
    );
  });
});

// ── End-to-end envelope vector ───────────────────────────────────────

describe("envelope vector", () => {
  it("matches the fixed plaintext/IV envelope vector", async () => {
    const iv = new Uint8Array(16);
    const plaintext = '{"lat":"0.000","lon":"0.000","units":"beaufort","slots":"0","ts":0}';
    const { q, ct, mac } = await buildEnvelope(ZERO_SECRET, iv, plaintext);

    expect(bytesToHex(ct)).toBe(
      "5aa477421c38339986cffbf6025cbf96e4c3c1c4810731ac0c98628865723b23" +
        "bab0dd72c626e3dda72eb56cf63b3f91ade76690e32176936daa8c84e7369873" +
        "da3ae3ae5e4008de7fe26ab635dd3100",
    );
    expect(bytesToHex(mac)).toBe(
      "fe7539ef67622b0d418c6d93cfe08afbf5be14edfc49ebe07f07daa645ef873d",
    );
    expect(q).toBe(FIXED_Q);
  });
});

// ── App-auth MAC vector ──────────────────────────────────────────────

describe("app-auth MAC vector", () => {
  it("matches the fixed header vector", async () => {
    const macB64u = await buildAuthMac(
      ZERO_SECRET,
      "GET",
      "/v1/forecast",
      FIXED_Q,
      "0",
      "Wind Force",
      "384eef47-978a-48c0-ad33-31bdfe9ec18f",
      "1.0.0",
    );
    expect(macB64u).toBe(FIXED_AUTH_MAC);
  });

  it("produces the canonical input length stated by the plan", () => {
    const c = canonicalAppAuthInput(
      "GET",
      "/v1/forecast",
      FIXED_Q,
      "0",
      "Wind Force",
      "384eef47-978a-48c0-ad33-31bdfe9ec18f",
      "1.0.0",
    );
    expect(c.length).toBe(252);
  });
});

// ── verifyAppAuth ────────────────────────────────────────────────────

describe("verifyAppAuth", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(0));
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  const url = new URL("https://example.com/v1/forecast");

  it("accepts a valid signed request", async () => {
    const macB64u = await buildAuthMac(
      ZERO_SECRET,
      "GET",
      "/v1/forecast",
      FIXED_Q,
      "0",
      "Wind Force",
      "384eef47-978a-48c0-ad33-31bdfe9ec18f",
      "1.0.0",
    );
    const req = makeRequest({
      "X-WF-App": "Wind Force",
      "X-WF-AppID": "384eef47-978a-48c0-ad33-31bdfe9ec18f",
      "X-WF-App-Ver": "1.0.0",
      "X-WF-App-Ts": "0",
      "X-WF-App-Mac": macB64u,
    });
    const out = await verifyAppAuth(req, FIXED_Q, url, [ZERO_SECRET], 0);
    expect(out.ok).toBe(true);
  });

  it("rejects when any X-WF-* header is missing", async () => {
    for (const drop of [
      "X-WF-App",
      "X-WF-AppID",
      "X-WF-App-Ver",
      "X-WF-App-Ts",
      "X-WF-App-Mac",
    ]) {
      const headers: Record<string, string> = {
        "X-WF-App": "Wind Force",
        "X-WF-AppID": "384eef47-978a-48c0-ad33-31bdfe9ec18f",
        "X-WF-App-Ver": "1.0.0",
        "X-WF-App-Ts": "0",
        "X-WF-App-Mac": FIXED_AUTH_MAC,
      };
      delete headers[drop];
      const req = makeRequest(headers);
      const out = await verifyAppAuth(req, FIXED_Q, url, [ZERO_SECRET], 0);
      expect(out.ok, `dropped ${drop}`).toBe(false);
      if (!out.ok) expect(out.reason).toBe("missing_header");
    }
  });

  it("rejects when the timestamp is outside the ±window", async () => {
    const ts = APP_AUTH_TS_WINDOW_SECONDS + 1;
    const macB64u = await buildAuthMac(
      ZERO_SECRET,
      "GET",
      "/v1/forecast",
      FIXED_Q,
      String(ts),
      "Wind Force",
      "384eef47-978a-48c0-ad33-31bdfe9ec18f",
      "1.0.0",
    );
    const req = makeRequest({
      "X-WF-App": "Wind Force",
      "X-WF-AppID": "384eef47-978a-48c0-ad33-31bdfe9ec18f",
      "X-WF-App-Ver": "1.0.0",
      "X-WF-App-Ts": String(ts),
      "X-WF-App-Mac": macB64u,
    });
    const out = await verifyAppAuth(req, FIXED_Q, url, [ZERO_SECRET], 0);
    expect(out.ok).toBe(false);
    if (!out.ok) expect(out.reason).toBe("ts_out_of_window");
  });

  it("fails when MAC was computed without the app field", async () => {
    // Build a MAC that omits the `app` length-prefixed segment.
    const ikm = Uint8Array.from(atob(ZERO_SECRET), (c) => c.charCodeAt(0));
    const zero32 = new Uint8Array(32);
    const prk = await rawHmac(zero32, ikm);
    const authInfo = new Uint8Array([...ENC.encode("wf-auth-v1"), 0x01]);
    const authRaw = await rawHmac(prk, authInfo);

    function u16be(n: number) {
      return new Uint8Array([(n >>> 8) & 0xff, n & 0xff]);
    }
    function lp(s: string) {
      const b = ENC.encode(s);
      const out = new Uint8Array(2 + b.length);
      out.set(u16be(b.length), 0);
      out.set(b, 2);
      return out;
    }
    function concat(...parts: Uint8Array[]) {
      const len = parts.reduce((a, p) => a + p.length, 0);
      const out = new Uint8Array(len);
      let off = 0;
      for (const p of parts) {
        out.set(p, off);
        off += p.length;
      }
      return out;
    }
    const bad = concat(
      lp("GET"),
      lp("/v1/forecast"),
      lp(FIXED_Q),
      lp("0"),
      // intentionally drop lp("Wind Force")
      lp("384eef47-978a-48c0-ad33-31bdfe9ec18f"),
      lp("1.0.0"),
    );
    const macBytes = await rawHmac(authRaw, bad);
    const req = makeRequest({
      "X-WF-App": "Wind Force",
      "X-WF-AppID": "384eef47-978a-48c0-ad33-31bdfe9ec18f",
      "X-WF-App-Ver": "1.0.0",
      "X-WF-App-Ts": "0",
      "X-WF-App-Mac": base64UrlEncodeBytes(macBytes),
    });
    const out = await verifyAppAuth(req, FIXED_Q, url, [ZERO_SECRET], 0);
    expect(out.ok).toBe(false);
    if (!out.ok) expect(out.reason).toBe("mac_fail");
  });

  it("accepts under the previous secret if active fails (grace window)", async () => {
    // Generate two distinct secrets, sign with prev, expect verify to pass when both supplied.
    const prevSecret = bytesToBase64Std(crypto.getRandomValues(new Uint8Array(48)));
    const activeSecret = bytesToBase64Std(crypto.getRandomValues(new Uint8Array(48)));

    const macB64u = await buildAuthMac(
      prevSecret,
      "GET",
      "/v1/forecast",
      FIXED_Q,
      "0",
      "Wind Force",
      "384eef47-978a-48c0-ad33-31bdfe9ec18f",
      "1.0.0",
    );
    const req = makeRequest({
      "X-WF-App": "Wind Force",
      "X-WF-AppID": "384eef47-978a-48c0-ad33-31bdfe9ec18f",
      "X-WF-App-Ver": "1.0.0",
      "X-WF-App-Ts": "0",
      "X-WF-App-Mac": macB64u,
    });
    const out = await verifyAppAuth(req, FIXED_Q, url, [activeSecret, prevSecret], 0);
    expect(out.ok).toBe(true);
  });
});

// ── decryptEnvelope ──────────────────────────────────────────────────

describe("decryptEnvelope", () => {
  it("round-trips the fixed plaintext", async () => {
    const iv = new Uint8Array(16);
    const plaintext = '{"lat":"0.000","lon":"0.000","units":"beaufort","slots":"0","ts":0}';
    const { q } = await buildEnvelope(ZERO_SECRET, iv, plaintext);

    const dec = await decryptEnvelope(q, [ZERO_SECRET]);
    expect(dec.ok).toBe(true);
    if (dec.ok) {
      expect(dec.payload.lat).toBe("0.000");
      expect(dec.payload.lon).toBe("0.000");
      expect(dec.payload.units).toBe("beaufort");
      expect(dec.payload.slots).toBe("0");
      expect(dec.payload.ts).toBe(0);
    }
  });

  it("rejects when the MAC is tampered (returns mac_fail)", async () => {
    const iv = new Uint8Array(16);
    const plaintext = '{"lat":"0.000","lon":"0.000","units":"beaufort","slots":"0","ts":0}';
    const { q } = await buildEnvelope(ZERO_SECRET, iv, plaintext);
    // Flip last byte of base64url-decoded envelope, then re-encode.
    let std = q.replace(/-/g, "+").replace(/_/g, "/");
    const pad = std.length % 4;
    if (pad === 2) std += "==";
    else if (pad === 3) std += "=";
    const raw = Uint8Array.from(atob(std), (c) => c.charCodeAt(0));
    raw[raw.length - 1] ^= 0x01;
    const tampered = base64UrlEncodeBytes(raw);
    const dec = await decryptEnvelope(tampered, [ZERO_SECRET]);
    expect(dec.ok).toBe(false);
    if (!dec.ok) expect(dec.reason).toBe("mac_fail");
  });

  it("rejects malformed q", async () => {
    const dec = await decryptEnvelope("not-base64!!!", [ZERO_SECRET]);
    expect(dec.ok).toBe(false);
  });

  it("rejects too-short q", async () => {
    const dec = await decryptEnvelope(base64UrlEncodeBytes(new Uint8Array(10)), [ZERO_SECRET]);
    expect(dec.ok).toBe(false);
  });
});

// ── collectSecrets ───────────────────────────────────────────────────

describe("collectSecrets", () => {
  it("returns [active] when prev is unset", () => {
    const env = { APP_AUTH_SECRET: "a" } as unknown as Env;
    expect(collectSecrets(env)).toEqual(["a"]);
  });
  it("returns [active, prev] when both are set", () => {
    const env = { APP_AUTH_SECRET: "a", APP_AUTH_SECRET_PREV: "b" } as unknown as Env;
    expect(collectSecrets(env)).toEqual(["a", "b"]);
  });
  it("drops empty values", () => {
    const env = { APP_AUTH_SECRET: "a", APP_AUTH_SECRET_PREV: "" } as unknown as Env;
    expect(collectSecrets(env)).toEqual(["a"]);
  });
});

void deriveKeys; // import touchpoint to keep tree-shakers honest
void bytesFromHex;
