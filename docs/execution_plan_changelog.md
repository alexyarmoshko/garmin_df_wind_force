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
- Addressed code review v2 findings (`docs/code_review.v2.md`):
  1. Fixed fetch state recorded before success: `_lastFetchTime`, `_lastFetchLatRad/Lon`, `_lastFetchedUnits/Slots` now set only in `onForecastReceived` on HTTP 200. Pending coordinates stored separately in `_pendingLatRad/Lon`. Failed fetches no longer suppress retries.
  2. Fixed position-blind forecast lookup: `findBestForecast()` now uses current GPS position via `FetchManager.currentLatDeg/Lon` to try `StorageManager.loadForecast()` (exact rounded match) first, then `StorageManager.loadNearestForecast()` (nearest within 2.5 km). Falls back to last stored entry only when no GPS fix available.
  3. Fixed look-ahead storage: look-ahead coordinates queued as `_laQueue` in `executeFetchCycle()` and consumed FIFO in `onLookAheadReceived()`. Data now stored via `StorageManager.storeForecast()` with proper rounded coordinates, enabling nearest-cache lookup and obeying the pruning limit.
  - PRG file size after fixes: 12.1 KB (release build).
- Addressed code review v3 finding (`docs/code_review.v3.md`):
  1. Fixed look-ahead callback-to-request matching: replaced FIFO queue + shared `onLookAheadReceived` with two dedicated coordinate slots (`_la1LatDeg/Lon`, `_la2LatDeg/Lon`) and two separate callbacks (`onLookAhead1Received`, `onLookAhead2Received`). Each callback uses its own pre-assigned coordinates regardless of completion order, eliminating the out-of-order corruption risk.
  - PRG file size after fix: 12.3 KB (release build).
- Addressed code review v4 finding (`docs/code_review.v4.md`):
  1. Fixed cross-cycle look-ahead coordinate corruption: replaced mutable shared coordinate slots (`_la1LatDeg/Lon`, `_la2LatDeg/Lon`) with a new `LookAheadCallback` class (`source/LookAheadCallback.mc`). Each look-ahead request creates its own `LookAheadCallback` instance that captures the coordinates immutably at dispatch time. The callback method `onReceived` uses the captured coordinates regardless of when the response arrives or whether a new fetch cycle has overwritten any shared state.
  - PRG file size after fix: 12.2 KB (release build).
- Addressed code review v5 finding (`docs/code_review.v5.md`):
  1. Fixed model-run race between `/model-status` and in-flight `/forecast`: `onForecastReceived()` now compares the response's `model_run` against `_lastModelRun`. If the response carries an older model run (meaning `/model-status` detected a newer run while the request was in flight), the data is still stored (valid for display) but `_lastFetchTime` is not committed, so the next compute cycle retriggers a fetch with the new model run's data.
  - PRG file size after fix: 12.3 KB (release build).
- Addressed code review v6 finding (`docs/code_review.v6.md`):
  1. Fixed `_lastModelRun` not initialized from forecast responses: `onForecastReceived()` now seeds `_lastModelRun` from the response's `model_run` field on non-stale success. This prevents the first `/model-status` poll after startup from forcing a redundant refetch when the cached forecast already came from the current model run.
  - PRG file size after fix: 12.2 KB (release build).

## 2026-03-14

- **Milestone 4 rework**: Discovered data fields cannot call `Communications.makeWebRequest()` directly — calls silently fail with no HTTP traffic, no callback, and no error. Rearchitected from direct-fetch to background service pattern.
  - Deleted `source/ForecastService.mc` (module with direct `makeWebRequest` calls — no longer needed).
  - Deleted `source/LookAheadCallback.mc` (look-ahead dispatch — deferred to future milestone).
  - Created `source/WindForceServiceDelegate.mc` (`(:background)` annotated `System.ServiceDelegate`): reads GPS position from `Application.Storage`, calls `makeWebRequest` in `onTemporalEvent()`, returns data via `Background.exit()`.
  - Rewrote `source/WindForceApp.mc` with `(:background)` annotation: `getServiceDelegate()`, `onBackgroundData()` to receive and store forecast data, `Background.registerForTemporalEvent()` with 5-minute Duration.
  - Simplified `source/FetchManager.mc` to position tracking only: `updatePosition()` persists GPS lat/lon to Storage for the background service. Removed all direct web request logic, fetch triggers, Haversine, destination-point math.
  - Added `Background` and `Positioning` permissions to `manifest.xml`.
  - Hardcoded 3-slot forecast request in service delegate (Storage sync between main/background processes unreliable in simulator).
  - End-to-end verified in simulator: GPS from GPX playback → background service fetches from CF Worker proxy → 3-slot wind data displayed correctly.
  - Memory usage: 13.5/28.5kB.
- Addressed code review v8 findings (`docs/code_review.v8.md`):
  1. Fixed staleness indicator using global `last_fetch_ts` instead of per-forecast timestamp: `onBackgroundData()` now injects `fetch_ts` into each forecast payload before storing via `StorageManager.storeForecast()`. `WindForceView.onUpdate()` reads `fetch_ts` from the displayed forecast dictionary, so the staleness indicator reflects the age of the data actually shown, not the most recent fetch for any location.
  2. Fixed no-GPS startup showing unrelated stale weather from a previous session: `findBestForecast()` now returns `null` immediately when `hasPosition` is false, instead of falling back to the most recently stored entry. Display shows "NO GPS" until a fix is acquired.
  3. Fixed proxy slot selection jumping slot 0 into the future after the half-hour mark: replaced single `selectEntry()` with `selectCurrentEntry()` (picks most recent entry at-or-before now) and `selectClosest()` (picks nearest to target timestamp). `buildResponse()` anchors slot 0 to the current hour, then offsets later slots from the current entry's time rather than `Date.now()`.
  4. Fixed strict Monkey C build (`-l 3`) regression: added `(:typecheck(false))` to methods referencing foreground-only symbols in `(:background)` classes (`getInitialView`, `onBackgroundData`), to `StorageManager` functions interacting with `Application.Storage` poly types (`storeForecast`, `loadForecast`, `pruneStorage`, `getStoredKeys`), and to `onForecastReceived` in the service delegate (framework `Dictionary` vs `PersistableType` mismatch). Fixed `splitFcKey` null safety (`substring()` returns nullable). Fixed `approxDistKm` return type (`Math.sqrt` returns `Double or Float`, added `.toDouble()`).
  - PRG file size after fixes: 11.4 KB (release build).
