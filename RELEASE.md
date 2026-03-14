# Release Notes

## Unreleased

### Added

- **Background service communication** (Milestone 4 rework): Data field fetches live wind forecast data via a background `ServiceDelegate` that fires every 5 minutes. Direct `makeWebRequest()` from data fields is not supported by Connect IQ — background services are required.
- **GPS position tracking**: `compute()` persists GPS coordinates to `Application.Storage` for the background service to read.
- **Offline fallback**: Forecast data is persisted in `Application.Storage` and displayed when connectivity is unavailable. Nearest cached grid point within 2.5 km is used if exact match unavailable.
- **Staleness indicator**: Prefixes display with `*` when data is older than 30 minutes (e.g., `*3(4)NE>5(6)S`).
- **Display engine** (Milestone 3): Adaptive layout showing 1-3 time slots depending on data field width. Auto font sizing selects largest readable font.
- **Cloudflare Worker proxy** (Milestone 2): Translates Met Eireann XML to compact JSON with KV caching. Supports unit conversion, slot selection, and veer/back computation server-side.
- **Project scaffolding** (Milestone 1): Connect IQ data field for Instinct 2X Solar targeting Kayak activities.

### Changed

- Replaced direct `makeWebRequest()` fetch strategy with background service pattern (`System.ServiceDelegate` + `Background.registerForTemporalEvent()`).
- Removed `ForecastService` module and `LookAheadCallback` class (superseded by `WindForceServiceDelegate`).
- Simplified `FetchManager` to GPS position tracking only (no fetch triggers, Haversine, or destination-point math).
- Added `Background` and `Positioning` permissions to manifest.
