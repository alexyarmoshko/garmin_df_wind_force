# Code Review v12

Date: 2026-03-15
Reviewer: Codex
Scope: Review of the current Milestone 5 implementation and the related project documentation after the follow-up fixes recorded in `docs/execution_plan_changelog.md`.

Requirement change incorporated in this version:

- Veering/backing tracking is no longer considered reliable enough to ship.
- The product should drop veering/backing semantics completely.
- A literal `"<"` separator should be shown between slots instead of veering/backing symbols.

## Findings

### 1. Medium: `settings_ver` still does not prove that a returned forecast was fetched with the current settings

The new guard versions `Application.Storage`, but the actual request parameters still come from `Application.Properties`. In `source/WindForceApp.mc:37-45`, `onSettingsChanged()` increments `settings_ver` and clears cached forecasts. In `source/WindForceServiceDelegate.mc:21-24`, the background service snapshots that version, but it separately reads `windUnits` and the forecast intervals from `Application.Properties` in `source/WindForceServiceDelegate.mc:41-42` and `source/WindForceServiceDelegate.mc:96-133`.

That means the app still has a wrong-settings acceptance path if `Application.Storage` and `Application.Properties` do not become visible to the background process at the same time. A temporal event can read the new `settings_ver`, still read the old property values, fetch old-unit or old-slot data, and return it with the new `sv`. `source/WindForceApp.mc:61-84` will then accept and store that payload as current.

This is the same user-facing failure mode as the earlier Milestone 5 findings, just narrowed to a cross-store synchronization race. The current fix rejects stale-version responses, but it does not bind the accepted response to the units/slots actually used on the wire.

Affected files:

- `source/WindForceApp.mc`
- `source/WindForceServiceDelegate.mc`

### 2. Medium: losing GPS after the first fix keeps rendering and fetching for the last known position

`FetchManager.updatePosition()` returns immediately when `info.currentLocation` is `null`, but it never clears `hasPosition` or the stored coordinates (`source/FetchManager.mc:20-36`). `WindForceView.findBestForecast()` treats `_fetchMgr.hasPosition` as the only gate for whether the app has a valid fix (`source/WindForceView.mc:114-131`).

After one successful fix, any later `null` location leaves `hasPosition = true`, so the field keeps rendering cached weather for the old coordinates instead of switching back to `NO GPS`. The background service also continues using the stale `bg_lat` and `bg_lon` values for future fetches. Garmin's SDK docs explicitly note that `Activity.Info` fields may return `null`, so this is not just a startup edge case.

Affected files:

- `source/FetchManager.mc`
- `source/WindForceView.mc`

### 3. Medium: the implementation still models veering/backing, but the updated requirement is a fixed `"<"` separator

The renderer still consumes the proxy's `veer` field and conditionally inserts it between adjacent slots (`source/DisplayRenderer.mc:50-55`). The data model also still names this field `veer` (`source/WindData.mc:8-21`), and the proxy/service path is still built around veer/back semantics.

Under the updated requirement, this behavior is no longer correct. The separator is now a pure formatting character, not a directional signal, so the watch should not depend on computed veer/back data at all. It should render a literal `"<"` between displayed slots every time, and the surrounding code and docs should stop describing those characters as "veering" or "backing".

This is broader than a narrow-layout display issue: it means the current output can still communicate a meaning the product no longer wants to promise.

Affected files:

- `source/DisplayRenderer.mc`
- `source/WindData.mc`
- `README.md`
- `docs/REQUIREMENTS.md`
- `docs/execution_plan.md`

### 4. Low: Milestone 5 documentation is still internally inconsistent with the implemented behavior

The Milestone 5 review fixes landed in code and in `docs/execution_plan_changelog.md`, but the main execution plan still describes a different state in several places:

- `docs/execution_plan.md:19` still shows Milestone 5 unchecked.
- `docs/execution_plan.md:498` still tells the reviewer to verify that interval 2 is clamped to `interval1 + 1`, but the actual code now suppresses the third slot when no valid later interval exists (`source/WindForceServiceDelegate.mc:118-123`).
- `docs/execution_plan.md:501` still says changing units while offline should keep showing old-unit data with a staleness indicator, but `source/WindForceApp.mc:44-45` now clears all cached forecasts immediately on settings change.
- The current docs still describe veering/backing as product behavior even though the updated requirement is to drop that logic and use a fixed `"<"` separator.

These mismatches make the plan unreliable as a validation checklist for the current Milestone 5 behavior.

Affected files:

- `docs/execution_plan.md`
- `source/WindForceApp.mc`
- `source/WindForceServiceDelegate.mc`

## Residual Risks and Validation Gaps

- I did not run the Connect IQ simulator or a physical-device test during this review.
- The cross-process visibility of `Application.Properties` during an active activity remains a device-validation gap, and it is directly relevant to Finding 1.

## Verification Performed

- Reviewed:
  - `source/WindForceApp.mc`
  - `source/WindForceView.mc`
  - `source/WindForceServiceDelegate.mc`
  - `source/FetchManager.mc`
  - `source/StorageManager.mc`
  - `source/DisplayRenderer.mc`
  - `source/WindData.mc`
  - `resources/properties/properties.xml`
  - `resources/settings/settings.xml`
  - `README.md`
  - `RELEASE.md`
  - `docs/REQUIREMENTS.md`
  - `docs/execution_plan.md`
  - `docs/execution_plan_changelog.md`
  - local Connect IQ SDK docs under `doc/Toybox/` and `doc/docs/Connect_IQ_FAQ/`
- Ran strict release build:
  - `monkeyc.bat -d instinct2x -f monkey.jungle -l 3 -r -o bin\review_v12.prg -y %USERPROFILE%\.ssh\developer_key`
  - Result: `BUILD SUCCESSFUL`
- Ran proxy type-check:
  - `npm run typecheck`
  - Result: `tsc --noEmit` completed successfully
