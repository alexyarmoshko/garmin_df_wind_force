# Code Review v13

Date: 2026-03-17
Reviewer: Codex
Scope: Review of the current Milestone 5 implementation and related documentation, with user clarification that invalid forecast-interval pairs should be prevented rather than silently normalized at request time.

## Findings

### 1. Medium: invalid interval pairs are still allowed in settings and silently rewritten instead of being prevented

The settings UI still exposes `forecastInterval1` and `forecastInterval2` as two independent `1-6h` lists in `resources/settings/settings.xml:11-30`. The service then repairs invalid pairs only when building the request in `source/WindForceServiceDelegate.mc:110-121`, and the foreground validator mirrors the same normalized request shape in `source/WindForceApp.mc:65-75`.

With the clarified product expectation, this is still incorrect Milestone 5 behavior. A user can select an invalid pair such as `5h` and `1h`, continue to see that pair in Garmin settings, but the app will actually fetch `0,5,6`. Likewise, `6h` plus any non-later third-slot choice is accepted in settings and then downgraded to a 2-slot request internally.

This is not just an implementation detail. The app currently permits a configuration the product says should be prevented, and the effective request can differ from the visible user selection.

Affected files:

- `resources/settings/settings.xml`
- `source/WindForceServiceDelegate.mc`
- `source/WindForceApp.mc`

### 2. Medium: the main documentation set still describes superseded architecture as if it were current behavior

`docs/REQUIREMENTS.md` still says the data field itself makes `Communications.makeWebRequest()` calls in `docs/REQUIREMENTS.md:68-82`, still describes `/v1/model-status` as a watch-side mechanism in `docs/REQUIREMENTS.md:117-119`, and still presents immediate startup fetches plus look-ahead fetching as part of the active behavior in `docs/REQUIREMENTS.md:197-204`.

The execution plan also contains stale current-state text. `docs/execution_plan.md:83-96` still says no source code exists yet, and `docs/execution_plan.md:469-471` still says existing data remains visible until the next background event after a settings change, even though `source/WindForceApp.mc:37-40` now clears cached forecasts immediately.

These mismatches make the docs unreliable for implementation review, validation, and future maintenance. For Milestone 5, that matters because the docs are supposed to define and confirm the shipped behavior.

Affected files:

- `docs/REQUIREMENTS.md`
- `docs/execution_plan.md`

### 3. Low: supported-device documentation and validation coverage do not match the declared support matrix

The manifest declares both `instinct2` and `instinct2x` in `manifest.xml:5-6`, but the public-facing docs still describe the project as targeting only Instinct 2X in `README.md:50-52` and `docs/execution_plan.md:115`.

With the clarified requirement that `instinct2` is supported, this is now a straightforward documentation and validation gap. The project metadata says one thing, while the docs and review guidance still frame the app as Instinct 2X-only. That makes it unclear whether Milestone 5 behavior has been validated on the smaller supported device and leaves the published support statement incomplete.

Affected files:

- `manifest.xml`
- `README.md`
- `docs/execution_plan.md`

## Residual Risks and Validation Gaps

- I did not run the Connect IQ simulator or a physical-device activity during this review.
- The real-time visibility of `Application.Properties` changes to the background service during an active activity remains an on-device validation gap.

## Verification Performed

- Reviewed:
  - `source/WindForceApp.mc`
  - `source/WindForceView.mc`
  - `source/WindForceServiceDelegate.mc`
  - `source/FetchManager.mc`
  - `source/StorageManager.mc`
  - `source/DisplayRenderer.mc`
  - `resources/settings/settings.xml`
  - `manifest.xml`
  - `README.md`
  - `docs/REQUIREMENTS.md`
  - `docs/execution_plan.md`
  - `docs/execution_plan_changelog.md`
- Ran proxy type-check:
  - `npm run typecheck`
  - Result: passed
- Ran strict Monkey C build directly with the SDK compiler:
  - `monkeyc.bat -w -d instinct2x -l 3 -f monkey.jungle -y %USERPROFILE%\.ssh\developer_key -o bin\review_current.prg`
  - Result: `BUILD SUCCESSFUL`
