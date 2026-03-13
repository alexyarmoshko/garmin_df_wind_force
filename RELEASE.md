# Release Notes

## Unreleased

### Added

- **Communication layer** (Milestone 4): Data field now fetches live wind forecast data from the Cloudflare Worker proxy using `Communications.makeWebRequest()`.
- **Fetch strategy**: Automatic fetch triggers based on distance moved (>1.5 km), time elapsed (>30 min), model run changes, or settings changes.
- **Look-ahead points**: Fetches forecast data for 2 points ahead along the current bearing at 2.5 km intervals, providing coverage during connectivity loss.
- **Offline fallback**: Forecast data is persisted in `Application.Storage` and displayed when connectivity is unavailable.
- **Staleness indicator**: Displays age in minutes (e.g., `*47m`) when data is older than 30 minutes.
- **Model status polling**: Checks for new HARMONIE model runs every 15 minutes.
- **Display engine** (Milestone 3): Adaptive layout showing 1-3 time slots depending on data field width. Auto font sizing.
- **Cloudflare Worker proxy** (Milestone 2): Translates Met Eireann XML to compact JSON with KV caching. Supports unit conversion and slot selection server-side.
- **Project scaffolding** (Milestone 1): Connect IQ data field for Instinct 2X Solar targeting Kayak activities.
