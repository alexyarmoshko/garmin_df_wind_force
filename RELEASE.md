# Release Notes

## 1.0.0 — Pre-release (in development)

This is the first planned release of Wind Force. Nothing has been published yet; the version string in `manifest.xml` is `1.0.0` but no build has been shipped to the Connect IQ Store. The sections below describe the intended scope of 1.0.0 as it stands today.

### Overview

Wind Force is a Garmin Connect IQ data field that displays live wind forecasts during Kayak activities on the Garmin Instinct 2 and Instinct 2X / 2X Solar. Forecast data is sourced from Met Éireann's HARMONIE-AROME model via a Cloudflare Worker proxy that translates the upstream XML into a compact JSON response (~300–500 bytes) suitable for the watch.

### Features

- **Live wind forecasts** displayed during Kayak activities on the Instinct 2 / 2X / 2X Solar (176 × 176 monochrome display, 32 KB data-field memory budget).
- **Multi-slot display**: 1–3 time slots in the compact `W/GD` format (e.g. `4/6S•3/5SW•3/6S`). The slot count adapts to the field width, and progressively drops slots if the rendered text overflows even at the smallest system font.
- **5 wind unit options**: Beaufort, Knots, mph, km/h, m/s — configurable via Garmin Connect Mobile or Garmin Express.
- **Configurable forecast intervals**: Two increment settings (`+1h` to `+6h`). The first is the offset from now; the second is the offset from the first. The proxy receives the absolute slot list `"0,i1,i1+i2"`. Maximum third-slot offset is `+12h`. All combinations are valid by design.
- **Integer speed values end-to-end**: Wind and gust speeds are rounded to integers from the proxy through the watch display. No fractional digits are ever shown — a deliberate guarantee for the smaller watch displays.
- **Staleness indicator**: The display is prefixed with `*` when the most recent forecast is older than 30 minutes.
- **Offline fallback**: Cached forecasts continue to display when connectivity is unavailable. If no exact cell is cached, the nearest cached grid point within 2.5 km is used.
- **Background service architecture**: A `System.ServiceDelegate` registered for temporal events at the Connect IQ minimum interval (5 minutes) fetches forecasts. GPS position from the foreground `compute()` is persisted to `Application.Storage` for the background process to read.
- **Immediate background fetch on first GPS fix**: When the data field acquires GPS (or reacquires it after a loss), the next background fetch is scheduled at the earliest time permitted by Garmin's 5-minute constraint rather than waiting for the next polling interval. This collapses the initial no-forecast window from up to 5 minutes to near-instant in the common case.
- **Activity-completion cleanup**: Cached forecasts and session GPS keys are cleared when an activity ends (saved or discarded), via dual hooks (`onActivityCompleted` in the background service plus `onTimerReset` in the foreground view). The next activity starts clean.
- **Diagnostic device logging**: Optional structured logging with human-readable timestamps via the `DiagnosticsLog` module, gated by the compile-time `ENABLE_DEVICE_LOGS` toggle. Zero runtime cost in release builds.

### Privacy-preserving forecast transport

The watch never sends `lat`/`lon` in URL query parameters. Coordinates, units, slots, and a request timestamp are wrapped into a single opaque Base64URL `q` parameter, encrypted with AES-256-CBC + HMAC-SHA256 under keys derived from `APP_AUTH_SECRET` via HKDF-style domain separation (labels `wf-enc-v1`, `wf-mac-v1`, `wf-auth-v1`). An `X-WF-App` / `X-WF-AppID` / `X-WF-App-Ver` / `X-WF-App-Ts` / `X-WF-App-Mac` header pair binds each request to the watch build via an HMAC over a length-prefixed canonical byte sequence.

The Worker enforces a 10-minute freshness window on `X-WF-App-Ts`, requires the decrypted payload `ts` to equal that header timestamp, rejects mixed-mode requests (both `q` and `lat`/`lon`) with `400`, and rejects malformed/tampered envelopes with `400` and missing/invalid app-auth with `403`. Cloudflare access logs and analytics no longer carry plaintext coordinates for watch traffic.

A deprecated plaintext `GET /v1/forecast?lat=&lon=` route is kept live, without app-auth, for the existing external test client. It will be removed once that client is retired.

The full wire format, key schedule, and interoperability test vectors are documented in the privacy transport design document.

### Proxy

- Cloudflare Worker (TypeScript) translating Met Éireann's HARMONIE-AROME XML into compact JSON.
- KV cache with a 7-hour forecast TTL and a 15-minute model-run TTL. KV cache keys hash the rounded coordinate pair (`forecast_<sha256(lat,lon)>_<model_run>`) so KV metadata does not carry plaintext coordinates.
- Unit conversion (Beaufort / knots / mph / km/h / m/s) and slot selection are performed server-side to minimise watch memory usage.
- Slot offsets are anchored to the current forecast entry's time (not wall-clock `now`), keeping slots aligned to hourly boundaries.

### Build infrastructure

- **Generated watch env**: The watch build emits `source/gen/Env.mc` with `FORECAST_URL`, `APP_AUTH_SECRET`, `APP_ID`, `APP_VER`, and `APP_NAME`. `APP_ID`/`APP_VER` are parsed from `manifest.xml`; `APP_NAME` is parsed from `resources/strings/strings.xml`. The secret is read from the explicit `APP_AUTH_SECRET_FILE`.
- **App-auth secret rotation**: Secrets live in `APP_AUTH_SECRET_DIR` (default `.keys/`) under a fixed `app_auth_<YYYYMMDD>_<NN>.txt` naming pattern. `make app-auth-secret-ensure` validates the active file (never creates). `make app-auth-secret-generate` writes a new non-overwriting timestamped candidate and prints the line to paste into `.env` to activate it. The active file is never switched implicitly. `make -C proxy secret-app-auth` / `secret-app-auth-prev` / `secret-app-auth-prev-clear` manage the Worker secrets. The Worker accepts the previous secret as `APP_AUTH_SECRET_PREV` for a short grace window after rotation.
- **Independent Makefiles**: The root `Makefile` owns the watch app and local secret generation. `proxy/Makefile` owns Worker configuration and deployment. Both source the same root `.env` (proxy via `ROOT_ENV_FILE`, resolving relative secret paths against the repository root). The root no longer carries `proxy-*` passthrough targets; proxy commands are invoked via `make -C proxy <target>`.
- **Generated Wrangler config**: `proxy/wrangler.jsonc.template` plus values from the root `.env` are combined by `yq` into `proxy/.wrangler/gen/wrangler.jsonc` on demand, following Cloudflare's current recommendation for new Workers projects.
- **Shared bash/make environment**: The root `.env` uses bash `export` syntax so the same file is consumable directly by shell scripts and by `make` (which sources it through bash).

### Testing

- **Watch app**: 25 Monkey C unit tests via `Toybox.Test` / `(:test)`, covering `GeoUtils.roundCoord` (6), `StorageManager.splitFcKey` (5), `StorageManager.approxDistKm` (4), `DisplayRenderer.slotCount` (6) and `renderWindSlot` (3), and `WindData` initialization. Stripped from release builds. Run with `monkeyc --unit-test` then `monkeydo -t`.
- **Proxy unit tests**: vitest suites in `proxy/test/` covering coordinate rounding, Beaufort and unit conversions (including the integer guarantee across all units with fractional inputs), direction labels, slot parsing/selection, hashed cache keys, and full response building.
- **Proxy crypto vectors**: Fixed-hex test vectors in `proxy/test/privacy.test.ts` for the HKDF-style key schedule (PRK, enc/mac/auth keys), envelope (ciphertext + MAC), and `X-WF-App-Mac`. These serve as independent cross-implementation ground truth, ensuring the watch and Worker cannot drift in canonicalization, label bytes, or layout. Additional tests cover MAC tampering, missing-header permutations, timestamp-window failures, payload/header `ts` mismatch, grace-window success under `APP_AUTH_SECRET_PREV`, omitted-field canonicalization injection, and mixed-mode rejection.
- **Proxy integration**: `handleForecast` integration tests exercise the encrypted `?q=` path end-to-end with an in-memory KV stub, plus the legacy plaintext path.
- **Proxy E2E**: 34 curl-based tests in `proxy/test/e2e.sh` against the deployed Worker covering routing, error handling, response structure, all five unit conversions, slot selection, coordinate rounding, and CORS headers.

### Technical details

- Supported devices: `instinct2` (006-B4071-00), `instinct2x` (006-B4394-00, 006-B3888-00).
- Minimum API level: `3.2.0` (required for `Toybox.Cryptography`).
- Background temporal event interval: 5 minutes (Connect IQ minimum).
- Coordinate grid resolution: 0.025° (~2.5 km, matching the HARMONIE grid).
- Permissions: `Background`, `Communications`, `Positioning`.
