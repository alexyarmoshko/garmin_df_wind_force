# Release Notes

## Unreleased

### Added

- **Immediate background fetch on GPS fix**: When the data field first acquires GPS (or reacquires it after a loss), a background fetch is scheduled at the earliest time permitted by Garmin's 5-minute constraint instead of waiting for the next polling interval. Reduces the initial no-forecast display duration from up to 5 minutes to near-instant in the common case.
- **Improved display formatting**: Slot separator changed from `<` to `•` (bullet) for better readability. "No forecast" state now shows `-/-•-/-•-/-` (matching the slot count) instead of `---`, giving a clearer visual cue that data is expected but not yet available.
- **Integer speed values guaranteed**: All wind and gust speed values are rounded to integers end-to-end (proxy → JSON → watch display). No decimal points are ever shown. This is a design guarantee for compatibility with smaller watch displays; integer precision is sufficient for paddling water activities.
- **Activity-completion cache pruning**: Cached forecasts and session GPS keys are cleared when an activity ends (saved or discarded). The next activity starts clean instead of showing stale data from a previous session. Dual cleanup hooks (`onActivityCompleted` in background + `onTimerReset` in foreground) ensure robustness.
- **Diagnostic logging**: New `DiagnosticsLog` module provides structured device logging with human-readable timestamps, controlled by a compile-time `ENABLE_DEVICE_LOGS` toggle. Event messages are short fixed strings; background fetch logs record the event and HTTP response code. Logging calls added to app lifecycle, settings changes, background data handling, and fetch events.

### Changed

- **Display path simplified**: The watch now uses a single-line renderer with only built-in Garmin system fonts. The experimental two-line layout code was removed.
- **Forecast intervals are now increments**: Both Immediate Interval and Imminent Interval settings are now relative offsets (+1h to +6h). Immediate is the offset from now; Imminent is the offset from the Immediate slot. Defaults changed from (3h, 6h) to (+3h, +3h), producing the same `0,3,6` slot query. All combinations are valid by design — the cross-field validation logic (`_validateIntervals()`) has been removed. Maximum third-slot offset is +12h.

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
- **Proxy unit tests**: 41 vitest tests covering coordinate rounding, Beaufort conversion, unit conversions (including integer guarantee), direction labels, slot parsing/selection, and full response building. Run with `cd proxy && npm test`.
- **Proxy E2E tests**: 34 curl-based tests against the deployed proxy covering routing, error handling, response structure, all 5 unit conversions, slot selection, coordinate rounding, and CORS headers. Run with `cd proxy && npm run test:e2e`.

### Technical Details

- Release PRG size: 17,516 bytes (53.5% of 32 KB data field memory limit)
- Supported devices: `instinct2` (006-B4071-00), `instinct2x` (006-B4394-00, 006-B3888-00)
- Minimum API level: 3.1.0
- Background temporal event interval: 5 minutes (Connect IQ minimum)
- Coordinate grid resolution: 0.025 degrees (~2.5 km, matching HARMONIE grid)
