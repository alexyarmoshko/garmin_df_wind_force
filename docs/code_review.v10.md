# Code Review v10

Date: 2026-03-14
Reviewer: Codex
Scope: Review of the current Milestone 5 implementation, focusing on settings handling, staleness behavior, and their interaction with the background-service architecture.

## Findings

### 1. High: Cached forecasts are reused after settings changes without validating that they were fetched for the current settings

`onSettingsChanged()` only requests a redraw in `source/WindForceApp.mc`, and `onUpdate()` in `source/WindForceView.mc` always renders whichever cached forecast dictionary is selected for the current or nearest grid point. The cached payload stored by `onBackgroundData()` retains the proxy response, but the view never checks whether that cached entry matches the currently selected wind units or interval settings before displaying it.

That creates two incorrect-display paths:

1. Immediately after changing units or intervals, the field redraws old cached data before the next background fetch happens.
2. Even after one refreshed fetch succeeds for the current position, moving into another cached grid point can resurrect older forecasts that were fetched under different unit or interval settings.

Because the display has no explicit unit label, the user cannot tell that the numbers are still in the old unit or correspond to old interval selections. Milestone 5 needs either cache invalidation/versioning by settings, or explicit compatibility checks before rendering cached entries.

Affected files:

- `source/WindForceApp.mc`
- `source/WindForceView.mc`
- `source/StorageManager.mc`

### 2. Medium: Interval clamping is not persisted and still produces duplicate slots when interval 1 is set to 6

The settings UI allows `forecastInterval1` and `forecastInterval2` to both be set to any value from 1 to 6. `WindForceServiceDelegate.getSlotsString()` tries to repair invalid combinations at request time by forcing `interval2` to be greater than `interval1`, but when `interval1` is 6 the repair collapses to `0,6,6`.

That means the wide layout can request duplicate second and third slots, producing repeated forecast entries and a misleading veer symbol between identical time steps. The corrected value is also not written back to the setting itself, so the UI can continue showing an invalid pair even though the effective request differs from what the user selected.

This should be fixed either by preventing invalid combinations in the settings UI, clamping and persisting the property value, or suppressing the third slot when no valid later interval exists.

Affected files:

- `resources/settings/settings.xml`
- `resources/properties/properties.xml`
- `source/WindForceServiceDelegate.mc`

## Residual Risks and Validation Gaps

I did not find a third static defect in this pass, but one Milestone 5 risk remains runtime-only:

- whether `Application.Properties` changes made during an active activity are visible to the background service on the next temporal event on a physical device

That needs device validation; static review cannot confirm it.

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
  - `monkeyc -d instinct2x -f monkey.jungle -r -o bin\review_v10.prg -y %USERPROFILE%\.ssh\developer_key`
  - Result: `BUILD SUCCESSFUL`
- Ran strict release build:
  - `monkeyc -d instinct2x -f monkey.jungle -l 3 -r -o bin\review_v10_l3.prg -y %USERPROFILE%\.ssh\developer_key`
  - Result: `BUILD SUCCESSFUL`
- I did not run the Connect IQ simulator or a physical-device test during this review.
