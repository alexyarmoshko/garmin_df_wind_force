# Execution Changelog

## 2026-03-20

- Simplified `source/WindForceView.mc` back to a single-line renderer and removed the uncommitted two-line display experiment.
- Removed the direction-mode setting and custom BMFont path from `source/DisplayRenderer.mc`, `resources/settings/settings.xml`, `resources/properties/properties.xml`, and `resources/strings/strings.xml`.
- Removed the BMFont resource definition and cleared the remaining files from `resources/fonts/`.
- Reduced logging call-site work in `source/WindForceApp.mc`, `source/WindForceServiceDelegate.mc`, and `source/FetchManager.mc` so logs are short fixed strings or response-code entries only.
- Updated `source/DiagnosticsLog.mc` to prepend human-readable timestamps centrally.
- Verified successful builds for both `bin/WindForce.prg` and `bin/WindForce-test.prg`.
- Removed 4 arrow-related unit tests from `test/Tests.mc` (25 Monkey C tests remain).
- Updated `docs/REQUIREMENTS.md`: removed arrows direction format, BMFont implementation note, and Direction markers setting. Wind direction is now always compact cardinal labels.
- Updated `docs/execution_plan.md`: superseded arrows decision, added removal and diagnostic logging decisions, updated DisplayRenderer interface, Surprises & Discoveries, Outcomes & Retrospective, and Revision History (Revision 12).
- Refactored forecast interval settings from absolute offsets to relative increments:
  - Both Immediate Interval and Imminent Interval now select +1h to +6h. Immediate is offset from now; Imminent is offset from Immediate. Proxy receives absolute values (`0,i1,i1+i2`).
  - `source/SettingsHelper.mc`: rewrote `getSlotsString()` to compute `slot3 = i1 + i2`. Removed `i2 > 6` suppression. Default for interval 2 changed from 6 to 3.
  - `source/WindForceApp.mc`: deleted `_validateIntervals()` (20 lines) and its call from `onSettingsChanged()`. No cross-field validation needed — all combinations valid by design.
  - `resources/properties/properties.xml`: `forecastInterval2` default changed from 6 to 3.
  - `resources/strings/strings.xml`: hour labels changed from `1h`-`6h` to `+1h`-`+6h`.
  - `proxy/src/index.ts`: `parseSlots()` range raised from 0-7 to 0-12. Updated test.
  - All 41 proxy tests pass. Strict build (`-l 3`) passes.
  - Updated `docs/REQUIREMENTS.md`, `README.md`, `RELEASE.md`, `docs/execution_plan.md` (Decision Log + Revision 13).
- Addressed code review v20 findings (`docs/code_review.v20.md`):
  1. **[Low] GPS quality gate — implemented**: `FetchManager.updatePosition()` now rejects positions with `currentLocationAccuracy < Position.QUALITY_POOR` (value 2). This filters out `QUALITY_LAST_KNOWN` (stale cached positions from a previous activity or satellite warmup), preventing background fetches for the wrong grid cell. A 2D fix (`QUALITY_POOR`) is accurate enough for the 2.5 km forecast grid.
  2. **[Low] Named constants for magic numbers — skipped**: The two thresholds (`0.0125` half-grid width, `0.001` ~100 m write throttle) are each used once with inline comments explaining the value and its physical meaning. Extracting them to named constants would add module-level declarations for single-use values without improving clarity beyond the existing comments. In a 32 KB memory-constrained app, avoiding unnecessary constant allocations is preferred.
  - Files modified: `source/FetchManager.mc`.
  - Strict build (`-l 3`) passes.

## 2026-03-19

- Addressed code review v18 findings (`docs/code_review.v18.md`) — proxy backend:
  1. **[Medium] Added global error handler**: Wrapped the `handleForecast()` call in the worker `fetch()` entry point with `try/catch`. Unhandled exceptions (upstream timeouts, invalid XML, parsing errors) now return a structured JSON `502` response via `errorResponse()` instead of Cloudflare's default HTML 500 error page. The Garmin watch always receives parseable JSON.
  2. **[Low] Added XML structure validation**: `parseWeatherXml()` in `met-eireann.ts` now uses optional chaining (`parsed?.weatherdata?.meta?.model` and `parsed?.weatherdata?.product?.time`) with explicit null checks. If Met Eireann returns an unexpected response (e.g. an HTML maintenance page), the function throws a descriptive `Error` instead of a raw `TypeError`. This error is caught by the new global handler (finding #1) and returned as JSON.
  - Files modified: `proxy/src/index.ts`, `proxy/src/met-eireann.ts`.
  - All 41 proxy tests pass.
- Addressed code review v16 findings (`docs/code_review.v16.md`):
  1. **Dead code — empty stubs removed**: Removed `FetchManager.initialize()` (empty body, no parent class) and `WindForceApp.onStart()` (empty `AppBase` override). Monkey C auto-generates default constructors for classes without explicit `initialize()`.
  2. **[High] Throttled Storage writes in FetchManager**: `updatePosition()` no longer writes `bg_lat`/`bg_lon` to `Application.Storage` every second. Writes are throttled to occur only when position changes by > 0.001 degrees (~100 m). On GPS loss, `_lastStoredLat/_lastStoredLon` are reset so the next fix always persists immediately. Reduces ~300 Storage writes per 5-minute background interval to ~2–5.
  3. **[Medium] Eliminated duplicated staleness calculation**: `DisplayRenderer.formatLayout()` now accepts `isStale as Boolean` instead of `fetchTimestamp as Number`. The staleness comparison (`Time.now() - fetch_ts > 30 min`) is computed once in `WindForceView.onUpdate()` and passed directly, removing the duplicate `Time.now()` call and threshold comparison from `DisplayRenderer`.
  4. **[Medium] Eliminated redundant font width re-check**: Added `_fontFits` member flag to `WindForceView`, set by `selectBuiltInFontSize()` and `selectCustomFontSize()`. These functions now check ALL font sizes (including the smallest) against `maxWidth` and report fit/no-fit via the flag. The outer slot-fitting loop reads `_fontFits` instead of re-measuring with `dc.getTextWidthInPixels()`. `maxWidth` is now passed as a parameter to avoid redundant `dc.getWidth() - 4` recomputation.
  5. **[Low] Removed redundant interval safety net**: The `if (i2 <= i1) { i2 = i1 + 1; }` guard in `SettingsHelper.getSlotsString()` was redundant because `WindForceApp._validateIntervals()` already corrects properties at the source on every `onSettingsChanged()` call.
  - Files modified: `source/FetchManager.mc`, `source/WindForceApp.mc`, `source/WindForceView.mc`, `source/DisplayRenderer.mc`, `source/SettingsHelper.mc`.
  - Strict build (`-l 3`) passes.
- Addressed code review v14 findings (`docs/code_review.v14.md`):
  1. **[High] Cached Storage & Properties access in onUpdate()**: `WindForceView.onUpdate()` no longer reads `Application.Properties` or `Application.Storage` on every 1-second tick. The `windDirection` property is cached in `_useArrows` and refreshed only on `onAppSettingsChanged()`. The best forecast dictionary (`_cachedDict`) and parsed forecast entries (`_cachedForecasts`) are cached and rebuilt only when invalidated. Cache invalidation triggers: new background data (`invalidateCache()` from `onBackgroundData`), GPS state change (acquired or lost), position moves to a different 0.025° grid cell (detected via threshold comparison in `compute()`), session reset, settings change, and slot count change in `onLayout()`.
  2. **[Medium] Eliminated per-tick object allocation**: `parseForecastEntries()` is called once when the cache is invalidated, not on every render tick. The `while (slots > 0)` fitting loop reuses the pre-cached `Array<WindData>` without allocating new objects. `DisplayRenderer.formatLayout()` now limits rendered entries to `min(forecasts.size(), slots)` so the full cached array can be passed directly without slicing.
  3. **[Medium] Consolidated duplicated settings parsing**: Created `source/SettingsHelper.mc` — a `(:background)` module with `getUnitsString()`, `getSlotsString()`, and `getInterval()`. Both `WindForceApp.onBackgroundData()` (formerly `_currentUnitsString()` / `_currentSlotsString()`) and `WindForceServiceDelegate.onTemporalEvent()` (formerly private `getUnitsString()` / `getSlotsString()` / `getInterval()`) now call the shared module. Single source of truth eliminates the risk of divergence when settings logic changes.
  - Files added: `source/SettingsHelper.mc`.
  - Files modified: `source/WindForceView.mc`, `source/WindForceApp.mc`, `source/WindForceServiceDelegate.mc`, `source/DisplayRenderer.mc`.
  - Strict build (`-l 3`) passes.
- Addressed code review v15 findings (`docs/code_review.v15.md`):
  1. **[Medium] Replaced substring loop with String.find() in splitFcKey()**: The char-by-char search that allocated a new 1-character string on every iteration via `substring(i, i+1)` is replaced with a single native `String.find("_")` call. Eliminates all intermediate string allocations when resolving nearest cached grid point.
  2. **[Medium] Cached display text and font**: Added `_displayText`, `_displayFont`, `_displayValid`, and `_wasStale` member variables to `WindForceView`. The string concatenation in `formatLayout()` and the font fitting loop now run only when forecast data changes, slot count changes, or the staleness state transitions (crosses the 30-minute threshold). On steady-state 1-second ticks, `onUpdate()` skips directly to `dc.drawText()` with the cached values.
  3. **[Minor] Removed dead Unicode arrow path from dirToArrow()**: The second code block generating Unicode arrows via `toChar().toString()` was unreachable — `dirToArrow()` is only called when `useArrows && hasPosition`, which always sets `useCustomGlyphPlaceholders = true`, so only the ASCII placeholder path executes. Removed the Unicode block, the `useCustomGlyphPlaceholders` guard in `dirToArrow()`, and the 8 pre-allocated `sArr*` module variables. Saves ~200 bytes of heap and makes the function's single responsibility clear.
  4. **[Low] Background memory headroom** (noted, no code change): proxy already limits response to max 3 slots with compact keys. Acknowledged as a deployment-level invariant.
  - Files modified: `source/StorageManager.mc`, `source/WindForceView.mc`, `source/DisplayRenderer.mc`.
  - Strict build (`-l 3`) passes.

## 2026-03-18

- **Direction Markers display setting** (Labels / Arrows):
  - New user setting `windDirection` (0=Labels, 1=Arrows) configurable via Garmin Connect Mobile / Express.
  - When set to Arrows, cardinal direction labels (N, NE, E, ...) are rendered as arrow glyphs showing where the wind blows TO (opposite of meteorological "from" convention): N→↓, NE→↙, E→←, SE→↖, S→↑, SW→↗, W→→, NW→↘.
  - Final custom-font implementation uses `windforce_s`, `windforce_m`, and `windforce_l` BMFonts generated by `tools/gen_windforce_font.py`. The glyph atlas stores digits 0-9, `/`, `-`, `*`, plus the slot separator and 8 arrows on ASCII placeholder ids (`|abcdefgh`).
  - When arrows mode is active and GPS is available, the display string is rendered using the custom BMFont with font auto-sizing cascading through lg→md→sm. Labels mode and `NO GPS` fall back to built-in Garmin fonts because the BMFont does not contain letters.
  - `DisplayRenderer` emits internal placeholder glyph ids only for the custom-font path because direct higher-Unicode BMFont glyph ids were unreliable in Connect IQ runtime loading.
  - This is a display-only setting — the proxy continues returning cardinal labels unchanged. No cache invalidation needed on change.
  - Files added: `resources/fonts/` (BMFont files + resources.xml), `tools/gen_windforce_font.py`.
  - Files modified: `resources/properties/properties.xml`, `resources/settings/settings.xml`, `resources/strings/strings.xml`, `source/DisplayRenderer.mc`, `source/WindForceView.mc`, `test/Tests.mc`.
  - 5 new unit tests: `dirToArrow` (cardinals, intercardinals, passthrough), `renderWindSlot` (arrow mode, label mode). Total: 29 Monkey C tests.
  - Release PRG: 17,516 bytes (53.5% of 32 KB limit). Feature cost: +3,488 bytes (fonts: +2,480, code: +1,008).
  - Updated `README.md`, `RELEASE.md`, `docs/REQUIREMENTS.md`, `docs/execution_plan.md`.
- Documented integer rounding guarantee for all wind/gust speed values as an explicit design decision:
  - Proxy `convertMps()` already applied `Math.round()` for all units; `mpsToBeaufort()` returns integers by table lookup. Watch-side `WindData` already stored values as Monkey C `Number` (integer). No code logic changes needed — the guarantee was already implemented but not formally documented.
  - Added JSDoc to `ForecastEntry` in `proxy/src/types.ts` documenting that `wind_speed` and `gust_speed` are always rounded integers.
  - Added JSDoc to `convertMps()` in `proxy/src/index.ts`.
  - Added dedicated proxy unit test (`"always returns integers for all units with fractional m/s inputs"`) that verifies `Number.isInteger()` across all 5 units with 9 fractional inputs (41 tests total, up from 40).
  - Added decision log entry in `docs/execution_plan.md`.
  - Updated `docs/REQUIREMENTS.md`: display format section and proxy response description now explicitly state the integer guarantee.
- Display formatting improvements:
  - Changed slot separator from `<` to `•` (bullet, `&#8226;`) in `resources/strings/strings.xml` for better readability on the monochrome display.
  - Replaced static "no forecast" string (`---`) with a dynamic slot-aware pattern (`-/-•-/-•-/-`). Each slot displays `-/-` (matching the `W/GD` format), separated by `•`, with the count matching the current display slot count. This gives users a clearer indication that forecast data is expected but not yet available.
  - `DisplayRenderer.formatLayout()` now accepts a `slots` parameter to build the no-forecast string dynamically. The overflow reduction loop in `WindForceView.onUpdate()` passes the current slot count, so the no-forecast display correctly reduces from 3 to 2 to 1 slot if the text doesn't fit.
  - Resource string `NoForecast` renamed to `NoForecastSlot` (value changed from `---` to `-/-`).
  - Updated `README.md`, `RELEASE.md`.
- **Milestone 7 completed**: Immediate background fetch on first GPS fix and activity-completion cache pruning.
  - **Part 1 — GPS fix trigger** (addresses `docs/field_test.v1.md`): data field showed `---` for up to 5 minutes after GPS lock because GPS acquisition does not trigger a background fetch.
    - Design: `FetchManager` gains a `gpsJustAcquired` flag set on the no-GPS → GPS transition. `WindForceView.compute()` detects the flag and calls `scheduleImmediateFetch()`, which re-registers the temporal event at the earliest legal `Time.Moment` using `Background.getLastTemporalEventTime()` + 5 min (or `Time.now()` if no prior event). `WindForceApp.onBackgroundData()` re-registers `Duration(5 * 60)` after every background event to restore the repeating schedule after the one-shot.
  - **Part 2 — Activity-end cache pruning** (addresses `docs/field_test.v2.md`): cached forecasts from a previous activity survive into the next session, displaying stale data.
    - Design: dual cleanup hooks for robustness. Primary: `Background.registerForActivityCompletedEvent()` registered in `getInitialView()`; `WindForceServiceDelegate.onActivityCompleted()` signals foreground via `Background.exit({"kind" => "session_end"})`; `onBackgroundData()` handles session-end by calling `StorageManager.clearAllForecasts()` and deleting `bg_lat`/`bg_lon`. Safety net: `WindForceView.onTimerReset()` performs the same cleanup from the foreground data-field lifecycle. Both hooks are intentionally redundant — if one fires before the other, the second is a harmless no-op.
    - `AppBase.onStop()` was explicitly rejected as a cleanup trigger because it fires on any app exit, not just activity completion.
  - Files to modify: `source/FetchManager.mc`, `source/WindForceView.mc`, `source/WindForceApp.mc`, `source/WindForceServiceDelegate.mc`.
  - Updated `docs/execution_plan.md`: Progress, Decision Log (2 entries), Milestone 7 section, Interfaces (WindForceView, WindForceServiceDelegate, FetchManager), Validation criteria 12–13, Outcomes & Retrospective, Revision History (Revisions 9–10).
  - Implementation:
    - `source/FetchManager.mc`: added `gpsJustAcquired` flag, set on no-GPS → GPS transition in `updatePosition()`.
    - `source/WindForceView.mc`: `compute()` detects `gpsJustAcquired` and calls `scheduleImmediateFetch()` (one-shot Moment via `Background.getLastTemporalEventTime()`). Added `onTimerReset()` as foreground safety net for activity-end cache cleanup.
    - `source/WindForceApp.mc`: `getInitialView()` registers for activity-completed events. `onBackgroundData()` handles `session_end` kind (clears cache + session keys without re-registering temporal event). Re-registers `Duration(5*60)` after all other background events to restore repeating schedule.
    - `source/WindForceServiceDelegate.mc`: added `onActivityCompleted()` callback, exits with `{"kind" => "session_end"}`.
    - Strict build (`-l 3`) passes. Release IQ built for all 3 device variants.
- Addressed code review v14 findings:
  1. Fixed session-end cleanup not stopping the temporal background schedule: both `onBackgroundData(session_end)` and `onTimerReset()` now call `Background.deleteTemporalEvent()`. Without this, a pending/repeating temporal event could fire after session end, fail (no GPS keys), and the generic handler would re-arm the 5-minute schedule indefinitely.
  2. Fixed background session-end path not resetting FetchManager state: extracted `WindForceView.resetSession()` (clears cache, GPS keys, `hasPosition`, `gpsJustAcquired`). `WindForceApp` now stores the view reference (`_view as Object?`) set in `getInitialView()`. The `session_end` handler calls `(_view as WindForceView).resetSession()` so the next activity's first GPS fix correctly triggers an immediate fetch. Previously, only the `onTimerReset()` foreground path reset these flags; if only the background path fired, `hasPosition` stayed `true` and the GPS acquisition trigger was skipped.
  3. Fixed session-end Storage cleanup gated behind live view reference: `onBackgroundData(session_end)` now calls `StorageManager.clearAllForecasts()` and deletes `bg_lat`/`bg_lon` unconditionally before the `_view` null check. When the app was inactive and background data is delivered on next launch (`_view` is null), the durable cleanup still runs. The `resetSession()` call on the view is additive — it resets in-memory FetchManager flags when the view is alive, but is not required for the Storage-level cleanup.

## 2026-03-17

- Fixed coordinate midpoint rounding drift across the watch app and proxy: `roundCoord()` now rounds via integer 0.025-degree grid steps (`value * 40`) instead of dividing by `0.025`. This prevents exact midpoint values such as `53.3375` from falling just below the `.5` threshold due to floating-point precision and incorrectly rounding down in Monkey C.

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
  - Both endpoints tested locally via `npm run dev` + `curl`.
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

- **Milestone 4 rework**: Discovered data fields cannot call `Communications.makeWebRequest()` directly - calls silently fail with no HTTP traffic, no callback, and no error. Rearchitected from direct-fetch to background service pattern.
  - Deleted `source/ForecastService.mc` (module with direct `makeWebRequest` calls - no longer needed).
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
  - Simplified staleness indicator from age-in-minutes suffix (`*47m`) to a `*` prefix (e.g., `*2(4)SW>3(5)W`). Avoids overflowing the display string and preserves all time slots.
  - PRG file size after fixes: 11.4 KB (release build).
- Addressed code review v9 findings (`docs/code_review.v9.md`):
  1. Rewrote `docs/execution_plan.md` Milestone 4 and related interface sections to describe the implemented background-service architecture rather than the removed direct-fetch design.
  2. Updated `docs/execution_plan.md` Milestone 5 to build settings handling on top of `WindForceServiceDelegate` and added an explicit on-device validation step for `Application.Properties` propagation during an active activity.
  3. Documented the deferred status of look-ahead fetching in both `docs/execution_plan.md` and `docs/REQUIREMENTS.md`, so the current delivered behaviour and the future target behaviour are clearly separated.
- **Milestone 5 initial implementation**: User settings UI.
  - Created `resources/settings/settings.xml` with list-type settings for wind units (Beaufort/Knots/mph/km·h/m·s), Immediate Interval (1-6h), and Imminent Interval (1-6h).
  - Added setting label strings to `resources/strings/strings.xml` (WindUnitsTitle, Beaufort, Knots, Mph, Kmh, Mps, Interval1Title, Interval2Title).
  - Added `onSettingsChanged()` to `WindForceApp.mc` to refresh the display when settings change via Garmin Connect Mobile / Express. Data updates on the next background temporal event.
  - Settings reading was already implemented in `WindForceServiceDelegate.mc` (`getUnitsString()`, `getInterval()`, `getSlotsString()`).
  - Staleness indicator was already implemented in `DisplayRenderer.mc` (`*` prefix when data >30 min old).
  - Strict build (`-l 3`) passes. PRG file size: 11.6 KB.
- Addressed code review v10 and v11 findings (`docs/code_review.v10.md`, `docs/code_review.v11.md`):
  1. Fixed cached forecasts rendered with wrong settings after unit/interval change: `onSettingsChanged()` now calls `StorageManager.clearAllForecasts()` to invalidate all cached forecast entries before requesting a redraw. Display shows `---` until the next background fetch completes with the new settings, preventing stale wrong-unit data from being displayed. New `clearAllForecasts()` method added to `StorageManager`.
  2. Fixed duplicate slots when `forecastInterval1 = 6`: `getSlotsString()` now suppresses the third slot entirely when `interval2` would exceed 6, emitting `0,6` instead of `0,6,6`. Eliminates duplicate forecast entries and misleading veer symbols between identical time steps.
  3. Fixed in-flight background responses repopulating cache after settings change: added `settings_ver` counter to `Application.Storage`. `onSettingsChanged()` increments the version; `WindForceServiceDelegate.onTemporalEvent()` captures it and includes it in the `Background.exit()` payload (`sv` field). `onBackgroundData()` compares the response version against the current version and discards mismatches. Even if Storage sync is delayed (background reads old version), the response is tagged with the old version and correctly rejected.
  - PRG file size after fixes: 12.1 KB (release build).

## 2026-03-15

- Display format and overflow improvements:
  - Changed slot format from `S(G)D` to `W/GD` (e.g., `9/23S` instead of `9(23)S`). Saves 2 characters per slot by replacing parentheses with `/` and removing the closing paren.
  - Added dynamic slot count reduction: `onUpdate()` now tries rendering with the maximum slot count first, then reduces slots one at a time until the text fits the field width. Prevents clipping when high wind speeds or two-letter directions produce long strings (e.g., `9/23S<11/25SE<18/42S`).
  - `parseForecastEntries()` now takes an explicit `slots` parameter instead of using the `_slots` instance variable, enabling the retry loop.
- Addressed code review v12 findings (`docs/code_review.v12.md`) and requirement change (drop veering/backing):
  1. Fixed `settings_ver` not proving response was fetched with current settings: replaced `settings_ver` counter with actual settings validation. `WindForceServiceDelegate` now includes the `units` and `slots` strings used in the request in the `Background.exit()` payload (`reqUnits`, `reqSlots`). `WindForceApp.onBackgroundData()` computes the expected values from `Application.Properties` and rejects mismatches. This eliminates the cross-store synchronisation race between `Application.Storage` and `Application.Properties`.
  2. Fixed GPS loss not clearing `hasPosition`: `FetchManager.updatePosition()` now sets `hasPosition = false` and deletes `bg_lat`/`bg_lon` from Storage when `info.currentLocation` is `null`. The display reverts to `NO GPS` and the background service stops fetching for stale coordinates.
  3. Dropped veering/backing semantics entirely per updated requirement. The `<` between adjacent time slots is now a literal formatting separator with no directional meaning. Changes span proxy (`veerSymbol()` removed, `veer` field removed from `ForecastEntry`), watch (`WindData.veer` removed, `DisplayRenderer` inserts literal `<`), and all documentation (`REQUIREMENTS.md`, `README.md`, `RELEASE.md`, `execution_plan.md`).
  4. Fixed execution plan inconsistencies: marked Milestone 5 as complete, updated validation checklist (third-slot suppression instead of clamping, cache clearing instead of staleness on settings change), removed all veering/backing references from plan text and interfaces.
  5. Fixed residual `REQUIREMENTS.md` inconsistencies: updated `/forecast` response example from raw fields (`wind_mps`, `wind_deg`, `wind_beaufort`, `gust_mps`) to the implemented pre-converted format (`wind_speed`, `gust_speed`, `wind_dir`) with `units` and `slots` query params; updated interval 2 clamping description to document third-slot suppression when clamped value exceeds 6h; replaced old `?(?)? ?` placeholder display with implemented `NO GPS` / `---`; replaced appended-asterisk/age-in-minutes staleness description with implemented `*` prefix.
- Versioned proxy API under `/v1` prefix:
  - Proxy routes changed from `/forecast` and `/model-status` to `/v1/forecast` and `/v1/model-status` in `proxy/src/index.ts`.
  - All responses now include an `api_version` field (`"v1"`) in the JSON body. Added to `ForecastResponse` and `ModelStatusResponse` types in `proxy/src/types.ts` and to `buildResponse()` / `handleModelStatus()` in `proxy/src/index.ts`.
  - Watch URL updated in `source/WindForceServiceDelegate.mc` to use `/v1/forecast`.
  - All endpoint references updated across `docs/REQUIREMENTS.md`, `docs/execution_plan.md`, `RELEASE.md`.

## 2026-03-17

- Addressed code review v13 findings (`docs/code_review.v13.md`):
  1. Fixed invalid interval pairs allowed in settings: added `_validateIntervals()` to `WindForceApp.onSettingsChanged()`. When `forecastInterval2 <= forecastInterval1`, corrected values are written back to `Application.Properties` so the Garmin Connect settings UI reflects the effective configuration. If `forecastInterval1 = 6` (no valid pair possible), it is reduced to 5 with interval 2 set to 6. Normalization in `getSlotsString()` and `_currentSlotsString()` retained as a safety net. Updated `docs/REQUIREMENTS.md` to describe validation-at-change-time instead of silent normalization.
  2. Fixed stale documentation describing superseded architecture:
     - `docs/REQUIREMENTS.md` architecture section rewritten to describe background-service pattern (`System.ServiceDelegate`, `Background.registerForTemporalEvent`, `Background.exit`) instead of direct `makeWebRequest()` calls.
     - `docs/REQUIREMENTS.md` `/v1/model-status` description updated: endpoint is available for external tooling, not called by the watch.
     - `docs/REQUIREMENTS.md` initial launch section rewritten to describe temporal event registration and `NO GPS` / `---` display states instead of immediate fetches and look-ahead.
     - `docs/execution_plan.md` Context and Orientation section updated from "no source code exists yet" to reflect the current repository structure.
     - `docs/execution_plan.md` Milestone 5 `WindForceApp.mc` section updated to describe `onSettingsChanged()` clearing cached forecasts and validating intervals, replacing the stale "existing display remains visible" description.
  3. Fixed device support documentation: `README.md` and `docs/execution_plan.md` updated to list both `instinct2` and `instinct2x` as supported devices, matching `manifest.xml`.
- Addressed code review v13 follow-up findings:
  4. Fixed inaccurate "equivalent normalization" wording in `docs/REQUIREMENTS.md`: the service-side safety net differs from the foreground correction in the `interval1 = 6` edge case (service suppresses the third slot rather than reducing interval 1). Documentation now describes this accurately.
  5. Fixed remaining Instinct 2X-only references in `docs/execution_plan.md`: updated Milestone 1 description, manifest description, M1 validation, M6 description, M6 validation, and acceptance criterion 1 to reference both supported devices. Fixed stale staleness description in acceptance criterion 8 from "asterisk or age in minutes" to "`*` prefix".
- **Milestone 6 completed**: Integration testing, optimisation, and deployment.
  - Memory optimisation: removed dead code (unused `model_status` handler, orphaned `last_model_run` Storage write, unused `Application.Storage` import in `WindForceApp.mc`, unused `Math`/`Position`/`Storage` imports in `WindForceView.mc`). Release PRG: 13,260 bytes (40.5% of 32 KB limit).
  - Proxy endpoint testing: verified all 5 unit conversions (beaufort, knots, mph, kmh, mps), 1/2/3-slot requests, and error handling (invalid params, missing params, wrong HTTP method) via curl.
  - Removed `/v1/model-status` endpoint from proxy: never called by the watch. Model run resolution is handled internally by `/v1/forecast` via KV cache. Removed `handleModelStatus()` function, `ModelStatusResponse` type, and route. Updated `docs/REQUIREMENTS.md`, `docs/execution_plan.md`, and `RELEASE.md`.
  - TypeScript type check (`tsc --noEmit`) passes clean.
  - Release IQ package built successfully for all 3 device variants (006-B4394-00, 006-B3888-00, 006-B4071-00).
  - Created `test/dublin_bay.gpx` for simulator GPS playback testing.
  - Cloudflare Worker proxy confirmed deployed and responding at `api-wind-force.kayakshaver.com`.
  - Updated `README.md` with Makefile build commands, side-loading instructions, and test directory.
  - Updated `RELEASE.md` with version 1.0.0 release notes.
  - Updated `docs/execution_plan.md` with Milestone 6 completion and Outcomes & Retrospective.
  - Simulator GUI tests (GPS playback, no-GPS display, settings changes, staleness indicator) documented as manual testing steps.
  - Added proxy unit tests (`proxy/test/index.test.ts`): 40 vitest tests covering `roundCoord`, `mpsToBeaufort`, `convertMps` (all 5 units), `degToCardinal`, `parseSlots`, `selectCurrentEntry`, `selectClosest`, and `buildResponse`. Exported pure functions from `proxy/src/index.ts` for testability. Removed unused `ModelStatusResponse` type.
  - Added proxy E2E tests (`proxy/test/e2e.sh`): 34 curl-based tests against the deployed proxy covering routing/error handling, response structure, unit conversions, slot selection, coordinate rounding, and CORS headers. Git Bash compatible (no `grep -P`, no `((var++))` arithmetic).
  - Added `vitest` dev dependency and `test`/`test:e2e` scripts to `proxy/package.json`. Updated `proxy/tsconfig.json` to include `test/` directory.
  - Updated `README.md` with testing section and proxy test directory in project structure.
  - Added Monkey C unit tests (`test/Tests.mc`): 24 tests using `Toybox.Test` / `(:test)` annotation covering `StorageManager.roundCoord` (6), `StorageManager.splitFcKey` (5), `StorageManager.approxDistKm` (4), `DisplayRenderer.slotCount` (6), `DisplayRenderer.renderWindSlot` (3), and `WindData` initialization (1). Tests are stripped from release builds via `(:test)` annotation. Updated `monkey.jungle` to include `test/` in `base.sourcePath`.
  - Updated `README.md` with watch app testing instructions and test directory description.
  - Updated `RELEASE.md` with watch app unit test details.
