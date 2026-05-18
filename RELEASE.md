# Release Notes

## Unreleased

### Added

- **Privacy-preserving forecast transport**: The watch no longer sends `lat`/`lon` as URL query parameters. Coordinates and request metadata are encrypted into a single opaque `q` Base64URL parameter using AES-256-CBC + HMAC-SHA256 under keys derived from `APP_AUTH_SECRET` via HKDF-style domain separation (`wf-enc-v1`, `wf-mac-v1`, `wf-auth-v1`). A new `X-WF-App` / `X-WF-AppID` / `X-WF-App-Ver` / `X-WF-App-Ts` / `X-WF-App-Mac` header pair binds the request to the watch build via an HMAC over the canonical request bytes. Cloudflare access logs and analytics no longer carry plaintext coordinates for watch traffic. The legacy plaintext `?lat=&lon=` path remains live as a deprecated route for the external test client. See the privacy transport design document.
- **Watch-side crypto helper**: New `source/WindForceCrypto.mc` (`(:background)` module) exposes `deriveKeys`, `encryptPayload`, `canonicalizeMacInput`, `hmacSha256`, `base64urlEncode`, and `buildPlaintextJson`. Uses `Toybox.Cryptography` (AES-256-CBC, HMAC-SHA256, secure random) and `Toybox.StringUtil` (Base64 decode/encode, UTF-8 byte conversion). IV is generated with `Cryptography.randomBytes(16)`; never derived from time or counters.
- **Proxy privacy module**: New `proxy/src/privacy.ts` exposes `deriveKeys`, `verifyAppAuth`, `decryptEnvelope`, and `collectSecrets`. The `/v1/forecast` handler dispatches between the encrypted `?q=` path (requires the full `X-WF-*` header set and a fresh timestamp; payload `ts` must equal `X-WF-App-Ts` inside the freshness window) and the legacy `?lat=&lon=` path. Mixed-mode requests (both `q` and `lat`/`lon`) are rejected with `400`.
- **App-auth secret rotation infrastructure**: `APP_AUTH_SECRET_DIR` (defaults to `.keys`) names the generation directory. `APP_AUTH_SECRET_FILE` names the explicit active secret file. `APP_AUTH_SECRET_PREV_FILE` names the previous file uploaded as `APP_AUTH_SECRET_PREV` during a grace window. `make app-auth-secret-generate` now creates a non-overwriting timestamped candidate at `<dir>/app_auth_<YYYYMMDD>_<NN>.txt` and prints the line operators must paste into `.env` to activate it; the active file is never switched implicitly. `make -C proxy secret-app-auth-prev` and `make -C proxy secret-app-auth-prev-clear` upload and remove the previous secret on the Worker.
- **Generated `APP_NAME` constant**: The build pipeline parses the `AppName` resource string from `resources/strings/strings.xml` and emits it as `Env.APP_NAME` alongside the existing `FORECAST_URL`, `APP_AUTH_SECRET`, `APP_ID`, and `APP_VER`. This avoids `WatchUi.loadResource()` calls from `(:background)` code in the encrypted-request flow.

### Changed

- **`app-auth-secret-ensure` no longer creates files**: It now only validates that the explicitly configured `APP_AUTH_SECRET_FILE` exists and is non-empty, and fails fast otherwise. Creation belongs to `app-auth-secret-generate`, so a typo in `.env` cannot silently activate a new secret.
- **Root and proxy Makefiles are now independent**: The root-level `proxy-*` passthrough targets have been removed. Proxy commands are invoked directly via `make -C proxy <target>`. The proxy `Makefile` resolves relative secret paths against the repository root (the directory containing `ROOT_ENV_FILE`).
- **Worker `Env` type extended**: `APP_AUTH_SECRET_PREV` is declared as an optional Worker secret. When set, the Worker tries it as a fallback for both app-auth verification and envelope decryption during a rotation grace window.

### Removed

- **Immediate background fetch on GPS fix**: When the data field first acquires GPS (or reacquires it after a loss), a background fetch is scheduled at the earliest time permitted by Garmin's 5-minute constraint instead of waiting for the next polling interval. Reduces the initial no-forecast display duration from up to 5 minutes to near-instant in the common case.
- **Improved display formatting**: Slot separator changed from `<` to `•` (bullet) for better readability. "No forecast" state now shows `-/-•-/-•-/-` (matching the slot count) instead of `---`, giving a clearer visual cue that data is expected but not yet available.
- **Integer speed values guaranteed**: All wind and gust speed values are rounded to integers end-to-end (proxy → JSON → watch display). No decimal points are ever shown. This is a design guarantee for compatibility with smaller watch displays; integer precision is sufficient for paddling water activities.
- **Activity-completion cache pruning**: Cached forecasts and session GPS keys are cleared when an activity ends (saved or discarded). The next activity starts clean instead of showing stale data from a previous session. Dual cleanup hooks (`onActivityCompleted` in background + `onTimerReset` in foreground) ensure robustness.
- **Diagnostic logging**: New `DiagnosticsLog` module provides structured device logging with human-readable timestamps, controlled by a compile-time `ENABLE_DEVICE_LOGS` toggle. Event messages are short fixed strings; background fetch logs record the event and HTTP response code. Logging calls added to app lifecycle, settings changes, background data handling, and fetch events.
- **Generated app-auth and manifest constants**: The watch build now generates `source/gen/Env.mc` with `FORECAST_URL`, `APP_AUTH_SECRET`, `APP_ID`, and `APP_VER`. `APP_AUTH_SECRET` is loaded from the file path configured in root `.env`, while app ID/version are parsed from `manifest.xml`.
- **App-auth secret file generation target**: Added `make app-auth-secret-ensure` to create the local secret file when missing or empty, and `make app-auth-secret-generate` to rotate it explicitly.

### Changed

- **Display path simplified**: The watch now uses a single-line renderer with only built-in Garmin system fonts. The experimental two-line layout code was removed.
- **Forecast intervals are now increments**: Both Immediate Interval and Imminent Interval settings are now relative offsets (+1h to +6h). Immediate is the offset from now; Imminent is the offset from the Immediate slot. Defaults changed from (3h, 6h) to (+3h, +3h), producing the same `0,3,6` slot query. All combinations are valid by design — the cross-field validation logic (`_validateIntervals()`) has been removed. Maximum third-slot offset is +12h.
- **Shared bash/make environment file**: The root `.env` now uses bash `export` syntax and the Makefile loads it by sourcing through bash. One `.env` file can now be reused directly by both `make` targets and shell scripts.
- **Wrangler config is now generated as JSONC**: The checked-in `proxy/wrangler.toml` has been replaced by `proxy/wrangler.jsonc.template` plus a generated `proxy/.wrangler/gen/wrangler.jsonc`. Root `make proxy-*` targets now delegate into `proxy/Makefile`, which uses `yq.exe` and values from the root `.env` to build the deployable config on demand. This follows Cloudflare's current recommendation to use `wrangler.jsonc` for new projects.
- **Proxy app metadata and secret plumbing**: The watch build still generates manifest-derived `APP_ID`, but the Wrangler template now owns any proxy-side app ID list manually via `APP_IDS`. `APP_AUTH_SECRET` remains a required Worker secret, and `make proxy-secret-app-auth` uploads it from the file path configured in root `.env`.
- **Build-time secret bootstrap**: `make build` now ensures `APP_AUTH_SECRET_FILE` exists before `source/gen/Env.mc` is generated, so the watch env generation step no longer depends on manual file creation.
- **Forecast KV cache keys are now hashed**: The proxy now stores raw forecast entries under `forecast_<sha256(rounded_lat,rounded_lon)>_<model_run>` instead of embedding rounded coordinates directly in the KV key. Cache behaviour is unchanged; the goal is to avoid plaintext coordinate-bearing metadata in KV.

### Removed

- **Direction Markers setting**: The labels/arrows toggle was removed. Wind direction is always shown as compact cardinal labels.
- **Custom BMFont resources**: The `windforce_*` font resource definitions are no longer part of the build.

### Fixed

- Corrected 0.025-degree coordinate midpoint rounding in both Monkey C and proxy code paths. Exact midpoint values like `53.3375` now round consistently to `53.350` instead of occasionally rounding down because of floating-point division drift.

## 1.0.0 (2026-03-17)

Initial release.

### Features

- **Live wind forecasts** from Met Eireann's HARMONIE-AROME model displayed during Kayak activities on Garmin Instinct 2 / 2X / 2X Solar.
- **Multi-slot display**: Shows 1-3 time slots (current + forecast hours) depending on data field width. Format: `W/GD` (e.g., `4/6S•3/5SW•3/6S`). Slot count adapts dynamically if text overflows.
- **5 wind unit options**: Beaufort, Knots, mph, km/h, m/s — configurable via Garmin Connect Mobile or Garmin Express.
- **Configurable forecast intervals**: Choose the hour offsets for the 2nd and 3rd time slots (1-6 hours each). Invalid pairs are auto-corrected.
- **Background service architecture**: Fetches data every 5 minutes via `System.ServiceDelegate` and `Background.registerForTemporalEvent()`. GPS position is persisted to `Application.Storage` for the background service.
- **Offline fallback**: Cached forecasts displayed when connectivity is unavailable. Nearest cached grid point within 2.5 km is used if exact match is not available.
- **Staleness indicator**: Display prefixed with `*` when data is older than 30 minutes.
- **Cloudflare Worker proxy**: Translates Met Eireann XML to compact JSON (~300-500 bytes) with KV caching (7h forecast TTL). Model run resolution cached internally (15min TTL). Unit conversion and slot selection performed server-side to minimise watch memory usage.

### Testing

- **Watch app unit tests**: 25 Monkey C tests (via `Toybox.Test` / `(:test)` annotation) covering `StorageManager.roundCoord` (6 tests), `StorageManager.splitFcKey` (5 tests), `StorageManager.approxDistKm` (4 tests), `DisplayRenderer.slotCount` (6 tests), `DisplayRenderer.renderWindSlot` (3 tests), and `WindData` initialization. Stripped from release builds. Run with `monkeyc --unit-test` then `monkeydo -t`.
- **Proxy unit tests**: 43 vitest tests covering coordinate rounding, Beaufort conversion, unit conversions (including integer guarantee), direction labels, slot parsing/selection, hashed KV cache keys, and full response building. Run with `cd proxy && npm test`.
- **Proxy E2E tests**: 34 curl-based tests against the deployed proxy covering routing, error handling, response structure, all 5 unit conversions, slot selection, coordinate rounding, and CORS headers. Run with `cd proxy && npm run test:e2e`.

### Technical Details

- Release PRG size: 17,516 bytes (53.5% of 32 KB data field memory limit)
- Supported devices: `instinct2` (006-B4071-00), `instinct2x` (006-B4394-00, 006-B3888-00)
- Minimum API level: 3.1.0
- Background temporal event interval: 5 minutes (Connect IQ minimum)
- Coordinate grid resolution: 0.025 degrees (~2.5 km, matching HARMONIE grid)
