# Execution Changelog

## 2026-03-12

- Created `docs/execution_plan.md` -- the initial execution plan covering all 6 milestones from project scaffolding through deployment.
- Researched Connect IQ SDK 8.2.3 structure, Monkey C patterns, and Instinct 2X Solar device constraints (176x176 monochrome, 32 KB data field memory limit, device ID `instinct2x`).
- Confirmed architecture: Cloudflare Worker proxy (TypeScript) translates Met Eireann XML to compact JSON; watch data field (Monkey C) fetches from proxy via paired phone.
- Key decisions recorded: use `WatchUi.DataField` (not `SimpleDataField`), TypeScript for CF Worker, proxy hosted under existing kayakshaver.com domain.
- Addressed all 5 findings from `docs/execution_plan_review.v1.md` (Revision 2 of execution plan):
  1. Fixed Wrangler route syntax: `[routes]` -> `[[routes]]` (TOML array-of-tables).
  2. Added 15-minute throttled polling interval for `/model-status` with `MODEL_STATUS_POLL_INTERVAL_SEC` constant.
  3. Standardised all internal coordinate and heading math to radians (confirmed `Activity.Info.currentHeading` is radians via SDK docs). Updated `computeLookAheadPoints` signature from `bearingDeg` to `bearingRad`.
  4. Replaced ambiguous settings file reference with prescriptive `resources/properties.xml` (confirmed for SDK 8.2.3).
  5. Added timestamps to all Progress entries and Revision History section per PLANS.md requirements.
  6. Added two new Decision Log entries (radians convention, model-status polling interval).
  7. Fixed all markdown lint warnings (double blank lines, blanks-around-lists, spaces-in-emphasis).
- **Milestone 1 completed**: Project scaffolding and static data field proof-of-concept.
  - Created `manifest.xml`, `monkey.jungle`, `source/WindForceApp.mc`, `source/WindForceView.mc`.
  - Created `resources/strings/strings.xml`, `resources/drawables/drawables.xml`, `resources/drawables/launcher_icon.svg`.
  - Used SVG launcher icon and resource subdirectories per SDK 8.2.3 conventions (deviation from original plan which specified PNG and flat layout).
  - Updated `.gitignore` with `bin/` and `*.prg`.
  - Build verified with `monkeyc -d instinct2x -l 3` (strict type checking) -- no errors or warnings.
  - Confirmed Instinct 2X is API level 3.4 (CIQ 3.4.3); `minApiLevel="3.1.0"` is compatible.
- **Milestone 2 completed**: Cloudflare Worker proxy with Met Eireann XML-to-JSON translation.
  - Created `proxy/` directory with `package.json`, `tsconfig.json`, `wrangler.toml`.
  - Created `proxy/src/types.ts`, `proxy/src/met-eireann.ts`, `proxy/src/index.ts`.
  - XML parsing via `fast-xml-parser`: extracts harmonie model run timestamp and point forecast wind data.
  - GET `/forecast?lat=&lon=` -- rounds coords to 0.025 deg, KV cache with 7h TTL, returns JSON with model_run + hourly forecasts.
  - GET `/model-status` -- returns latest harmonie model run timestamp, KV cache with 15min TTL.
  - CORS headers, input validation, error handling all verified.
  - Both endpoints tested locally via `wrangler dev` + `curl`.
  - Updated `.gitignore` with `node_modules/` and `.wrangler/`.
- Addressed code review v1 findings (`docs/code_review.v1.md`):
  1. Fixed `/forecast` dropping the current hour's slot — changed time filter from `now` to `now - 1h`.
  2. Fixed cache key not recomputed after model run update — `cacheKey` now recalculated when `freshModelRun` differs.

## 2026-03-13

- **Milestone 3 completed**: Data field display engine.
  - Created `source/WindData.mc` (data class for forecast entries).
  - Created `source/DisplayRenderer.mc` (module: slot rendering, direction labels, veer/back symbols, unit conversion, layout formatting).
  - Updated `source/WindForceView.mc` to use DisplayRenderer with hardcoded sample data and auto font sizing.
  - Layout adapts to field width: 1-slot (<90px), 2-slot (90-149px), 3-slot (>=150px).
  - Verified in simulator: small slot shows "3(4)NE", large slot shows "3(4)NE>5(6)S>3(5)SW".
  - Memory usage: 9.4/28.5kB.
- **Architectural change documented (Revision 6)**: Move unit conversion, Beaufort lookup, and direction labelling from the watch to the proxy.
  - `/forecast` endpoint now accepts `units` query parameter (`beaufort`, `knots`, `mph`, `kmh`, `mps`).
  - Raw data cached in KV; conversion applied on the fly per request.
  - New response shape: `wind_speed` (int), `gust_speed` (int), `wind_dir` (cardinal label), `wind_deg` (raw degrees), top-level `units` field.
  - Watch-side `DisplayRenderer` simplified: removed `convertSpeed()`, `mpsToBeaufort()`, `directionLabel()`.
  - `WindData` now holds pre-converted integers + direction string instead of raw floats.
  - `ForecastService.fetchForecast()` gains `units` parameter; `FetchManager` tracks `_lastFetchedUnits` as a fetch trigger.
  - `SettingsManager` gains `getWindUnitsString()` to map numeric setting to proxy-compatible string.
  - Unit setting change triggers refetch (option 1) — brief 1-3s delay while new data is fetched.
  - TypeScript `types.ts` splits into `RawForecastEntry` (internal) and `ForecastEntry` (response); `ForecastResponse` gains `units` field.
  - Decision Log entry added. Execution plan updated across Milestones 2-5 and Interfaces section.
- **Architectural change documented (Revision 7)**: Move slot selection and veer/back computation from watch to proxy.
  - `/forecast` endpoint gains `slots` query parameter (comma-separated hour offsets, e.g., `0,3,6`, max 3 values, default `0`).
  - Proxy selects closest forecast entry for each offset, computes veer/back between consecutive selected entries.
  - Response field `wind_deg` replaced by `veer` (`">"`, `"<"`, or `null` for first entry).
  - Watch-side `DisplayRenderer` further simplified: removed `veerBackSymbol()`, `formatLayout()` no longer does interval selection.
  - `WindData` field `windDeg` replaced by `veer` (String or Null).
  - `ForecastService.fetchForecast()` gains `slots` parameter; `FetchManager` builds slots string from slot count + interval settings, tracks `_lastFetchedSlots` as fetch trigger.
  - Interval setting change now triggers refetch (same as unit change).
  - TypeScript `ForecastEntry` field `wind_deg` replaced by `veer: string | null`.
  - Decision Log entry updated to include slot selection and veer/back.
- **Milestone 4 completed**: Communication layer and fetch strategy.
  - Created `source/ForecastService.mc` (module: `fetchForecast()` and `fetchModelStatus()` wrapping `Communications.makeWebRequest()`).
  - Created `source/StorageManager.mc` (module: `storeForecast()`, `loadForecast()`, `loadNearestForecast()`, `pruneStorage()`, `roundCoord()` wrapping `Application.Storage`).
  - Created `source/FetchManager.mc` (class: `executeFetchCycle()` with distance/time/model-run/settings triggers, look-ahead point computation, Haversine distance, destination-point formula).
  - Updated `source/WindForceView.mc`: `compute()` calls `FetchManager.executeFetchCycle()`, `onUpdate()` loads forecasts from storage and passes to `DisplayRenderer`.
  - Updated `source/DisplayRenderer.mc`: added staleness indicator (age in minutes with `*` prefix when data >30 min old), improved unavailable data display (`?(?)? ?`).
  - Created `resources/properties/properties.xml` with default property values (windUnits=0, forecastInterval1=3, forecastInterval2=6) required by FetchManager.
  - FetchManager is a class (not module) because `Communications.makeWebRequest()` callbacks require `method(:name)` which needs an instance `self`.
  - PRG file size: 11.6 KB (release build). ~20 KB headroom remaining.
