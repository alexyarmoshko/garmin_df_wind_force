import type { Env } from "./types";

export interface DerivedKeys {
  encKey: CryptoKey;
  macKey: CryptoKey;
  authKey: CryptoKey;
}

export interface DecryptedPayload {
  lat: string;
  lon: string;
  units: string;
  slots: string;
  ts: number;
}

const ENC_LABEL = "wf-enc-v1";
const MAC_LABEL = "wf-mac-v1";
const AUTH_LABEL = "wf-auth-v1";

const APP_AUTH_TS_WINDOW_S = 600;

function base64ToBytes(b64: string): Uint8Array {
  const binary = atob(b64);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

function base64UrlToBytes(b64url: string): Uint8Array {
  let s = b64url.replace(/-/g, "+").replace(/_/g, "/");
  const pad = s.length % 4;
  if (pad === 2) s += "==";
  else if (pad === 3) s += "=";
  else if (pad === 1) throw new Error("invalid base64url length");
  return base64ToBytes(s);
}

function concatBytes(...parts: Uint8Array[]): Uint8Array {
  let len = 0;
  for (const p of parts) len += p.length;
  const out = new Uint8Array(len);
  let off = 0;
  for (const p of parts) {
    out.set(p, off);
    off += p.length;
  }
  return out;
}

async function hmacSha256(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const ck = await crypto.subtle.importKey(
    "raw",
    key as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", ck, data as BufferSource);
  return new Uint8Array(sig);
}

async function importHmacKey(raw: Uint8Array): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    raw as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

async function importAesKey(raw: Uint8Array): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    raw as BufferSource,
    { name: "AES-CBC" },
    false,
    ["decrypt"],
  );
}

const TEXT_ENCODER = new TextEncoder();

/** Derive enc/mac/auth keys from the standard-Base64 APP_AUTH_SECRET text. */
export async function deriveKeys(secret: string): Promise<DerivedKeys> {
  const ikm = base64ToBytes(secret);
  const zero32 = new Uint8Array(32);
  const prk = await hmacSha256(zero32, ikm);

  const one = new Uint8Array([0x01]);
  const encInfo = concatBytes(TEXT_ENCODER.encode(ENC_LABEL), one);
  const macInfo = concatBytes(TEXT_ENCODER.encode(MAC_LABEL), one);
  const authInfo = concatBytes(TEXT_ENCODER.encode(AUTH_LABEL), one);

  const encRaw = await hmacSha256(prk, encInfo);
  const macRaw = await hmacSha256(prk, macInfo);
  const authRaw = await hmacSha256(prk, authInfo);

  const [encKey, macKey, authKey] = await Promise.all([
    importAesKey(encRaw),
    importHmacKey(macRaw),
    importHmacKey(authRaw),
  ]);
  return { encKey, macKey, authKey };
}

function u16be(n: number): Uint8Array {
  return new Uint8Array([(n >>> 8) & 0xff, n & 0xff]);
}

function lenPrefixed(s: string): Uint8Array {
  const bytes = TEXT_ENCODER.encode(s);
  return concatBytes(u16be(bytes.length), bytes);
}

/** Canonical byte sequence for the X-WF-App-Mac input. */
export function canonicalAppAuthInput(
  method: string,
  path: string,
  q: string,
  ts: string,
  app: string,
  appId: string,
  appVer: string,
): Uint8Array {
  return concatBytes(
    lenPrefixed(method),
    lenPrefixed(path),
    lenPrefixed(q),
    lenPrefixed(ts),
    lenPrefixed(app),
    lenPrefixed(appId),
    lenPrefixed(appVer),
  );
}

function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export type VerifyAppAuthOutcome =
  | { ok: true; ts: number }
  | { ok: false; reason: "missing_header" | "bad_ts" | "ts_out_of_window" | "mac_fail" };

/**
 * Verify the X-WF-App-Mac header against the canonical input keyed by auth_key.
 * Uses `secrets` in order; the first secret that yields a valid MAC succeeds.
 */
export async function verifyAppAuth(
  request: Request,
  q: string,
  url: URL,
  secrets: string[],
  nowS: number,
): Promise<VerifyAppAuthOutcome> {
  const app = request.headers.get("X-WF-App");
  const appId = request.headers.get("X-WF-AppID");
  const appVer = request.headers.get("X-WF-App-Ver");
  const tsStr = request.headers.get("X-WF-App-Ts");
  const macB64u = request.headers.get("X-WF-App-Mac");

  if (!app || !appId || !appVer || !tsStr || !macB64u) {
    return { ok: false, reason: "missing_header" };
  }

  const ts = Number(tsStr);
  if (!Number.isFinite(ts) || !Number.isInteger(ts)) {
    return { ok: false, reason: "bad_ts" };
  }
  if (Math.abs(nowS - ts) > APP_AUTH_TS_WINDOW_S) {
    return { ok: false, reason: "ts_out_of_window" };
  }

  let macBytes: Uint8Array;
  try {
    macBytes = base64UrlToBytes(macB64u);
  } catch {
    return { ok: false, reason: "mac_fail" };
  }
  if (macBytes.length !== 32) {
    return { ok: false, reason: "mac_fail" };
  }

  const canonical = canonicalAppAuthInput(
    request.method,
    url.pathname,
    q,
    tsStr,
    app,
    appId,
    appVer,
  );

  for (const secret of secrets) {
    if (!secret) continue;
    const { authKey } = await deriveKeys(secret);
    const expected = new Uint8Array(
      await crypto.subtle.sign("HMAC", authKey, canonical as BufferSource),
    );
    if (timingSafeEqual(expected, macBytes)) {
      return { ok: true, ts };
    }
  }
  return { ok: false, reason: "mac_fail" };
}

export type DecryptOutcome =
  | { ok: true; payload: DecryptedPayload }
  | { ok: false; reason: "bad_q" | "mac_fail" | "decrypt_fail" | "bad_json" };

export async function decryptEnvelope(q: string, secrets: string[]): Promise<DecryptOutcome> {
  let raw: Uint8Array;
  try {
    raw = base64UrlToBytes(q);
  } catch {
    return { ok: false, reason: "bad_q" };
  }
  if (raw.length < 16 + 32 + 16) {
    return { ok: false, reason: "bad_q" };
  }
  const iv = raw.subarray(0, 16);
  const tag = raw.subarray(raw.length - 32);
  const ct = raw.subarray(16, raw.length - 32);
  const ivCt = raw.subarray(0, raw.length - 32);

  let macMatched = false;
  let decrypted: Uint8Array | null = null;
  for (const secret of secrets) {
    if (!secret) continue;
    const { encKey, macKey } = await deriveKeys(secret);
    const expectedMac = new Uint8Array(
      await crypto.subtle.sign("HMAC", macKey, ivCt as BufferSource),
    );
    if (!timingSafeEqual(expectedMac, tag)) continue;
    macMatched = true;
    try {
      const pt = await crypto.subtle.decrypt(
        { name: "AES-CBC", iv: iv as BufferSource },
        encKey,
        ct as BufferSource,
      );
      decrypted = new Uint8Array(pt);
      break;
    } catch {
      // padding error etc.; try next secret in case of a key-rotation edge
    }
  }

  if (!decrypted) {
    return { ok: false, reason: macMatched ? "decrypt_fail" : "mac_fail" };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder().decode(decrypted));
  } catch {
    return { ok: false, reason: "bad_json" };
  }
  if (!parsed || typeof parsed !== "object") {
    return { ok: false, reason: "bad_json" };
  }
  const p = parsed as Record<string, unknown>;
  if (
    typeof p.lat !== "string" ||
    typeof p.lon !== "string" ||
    typeof p.units !== "string" ||
    typeof p.slots !== "string" ||
    typeof p.ts !== "number"
  ) {
    return { ok: false, reason: "bad_json" };
  }
  return {
    ok: true,
    payload: {
      lat: p.lat,
      lon: p.lon,
      units: p.units,
      slots: p.slots,
      ts: p.ts,
    },
  };
}

/** Collect secrets in the order [active, previous (if set)]. */
export function collectSecrets(env: Env): string[] {
  const out: string[] = [];
  if (env.APP_AUTH_SECRET) out.push(env.APP_AUTH_SECRET);
  if (env.APP_AUTH_SECRET_PREV) out.push(env.APP_AUTH_SECRET_PREV);
  return out;
}

export const APP_AUTH_TS_WINDOW_SECONDS = APP_AUTH_TS_WINDOW_S;
