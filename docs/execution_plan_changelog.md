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
