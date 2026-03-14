# Code Review v11

Date: 2026-03-14
Reviewer: Codex
Scope: Review of the current Milestone 5 implementation after adding the settings UI resources and `onSettingsChanged()`.

## Findings

### 1. High: Settings changes still allow stale old-setting forecasts to be rendered as if they matched the current configuration

`onSettingsChanged()` in `source/WindForceApp.mc` now forces an immediate redraw, but `WindForceView.onUpdate()` still renders whichever cached forecast dictionary is available for the current or nearest grid point without validating that it was fetched for the current wind-unit and interval settings. `onBackgroundData()` stores the proxy payload plus `fetch_ts`, but no compatibility check is applied before rendering.

That means Milestone 5 still has two incorrect-display paths:

1. Immediately after a settings change, the forced redraw can show cached data fetched under the old settings until the next background fetch completes.
2. Even after one refreshed fetch succeeds for the current position, moving into another cached grid point can surface an older forecast that was fetched under different unit or interval settings.

Because the display has no explicit unit label, the user cannot tell that the numbers are stale with respect to settings rather than weather age. Adding the settings UI did not address this; it now makes the immediate mismatch deterministic because `onSettingsChanged()` explicitly repaints the old cached value.

Affected files:

- `source/WindForceApp.mc`
- `source/WindForceView.mc`
- `source/StorageManager.mc`

### 2. Medium: Invalid interval combinations are still repaired only transiently, and `interval1 = 6` still collapses to duplicate slots

The new settings UI exposes `forecastInterval1` and `forecastInterval2` as independent 1-6 hour lists, but `WindForceServiceDelegate.getSlotsString()` still corrects invalid combinations only when building the request. If `interval1` is 6, the current logic produces `0,6,6`, so the second and third slots can be duplicates with a misleading veer symbol between identical time steps.

The corrected value is also not written back to the property itself, so the settings UI can continue showing a pair that does not match the effective request. Milestone 5 therefore still lacks a coherent rule for invalid interval combinations at the user-settings layer.

Affected files:

- `resources/settings/settings.xml`
- `resources/properties/properties.xml`
- `source/WindForceServiceDelegate.mc`

## Residual Risks and Validation Gaps

I did not find a third new static defect in this pass, but the runtime validation gap from the previous review still applies:

- whether `Application.Properties` changes made during an active activity are visible to the background service on the next temporal event on a physical device

Static review cannot confirm that behavior.

## Verification Performed

- Reviewed:
  - `source/WindForceApp.mc`
  - `source/WindForceView.mc`
  - `source/WindForceServiceDelegate.mc`
  - `source/StorageManager.mc`
  - `source/DisplayRenderer.mc`
  - `resources/properties/properties.xml`
  - `resources/settings/settings.xml`
  - `resources/strings/strings.xml`
  - `docs/execution_plan.md`
  - `docs/execution_plan_changelog.md`
  - `RELEASE.md`
- Ran release build:
  - `monkeyc -d instinct2x -f monkey.jungle -r -o bin\review_v11.prg -y %USERPROFILE%\.ssh\developer_key`
  - Result: `BUILD SUCCESSFUL`
- Ran strict release build:
  - `monkeyc -d instinct2x -f monkey.jungle -l 3 -r -o bin\review_v11_l3.prg -y %USERPROFILE%\.ssh\developer_key`
  - Result: `BUILD SUCCESSFUL`
- I did not run the Connect IQ simulator or a physical-device test during this review.
