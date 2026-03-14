# Code Review v8

Date: 2026-03-14
Reviewer: Codex
Scope: Review of the current implementation with focus on the Milestone 4 background-service rework and related fixes.

## Findings

### 1. Staleness indicator is global, not tied to the forecast being displayed

Severity: Medium

`last_fetch_ts` is updated on every successful background fetch in `source/WindForceApp.mc`, and the renderer always uses that single timestamp when deciding whether to show stale data. Cached forecast entries stored by `StorageManager.storeForecast()` do not carry their own fetch time.

This means the field can display an older exact-match or nearest-match cached forecast while still appearing fresh if some other location was fetched recently. That weakens the stale-data signal during offline fallback, which is when the indicator matters most.

Affected files:

- `source/WindForceApp.mc`
- `source/WindForceView.mc`
- `source/DisplayRenderer.mc`
- `source/StorageManager.mc`

### 2. No-GPS startup can render unrelated stale weather from a previous session

Severity: Medium

When `_fetchMgr.hasPosition` is false, `WindForceView.findBestForecast()` falls back to the most recently stored forecast entry instead of returning no data. Because `DisplayRenderer.formatLayout()` only shows `NO GPS` when there are no forecasts at all, an indoor start or slow GPS acquisition can show wind data from the previous location/session.

That is misleading for the user and conflicts with the intended no-fix behavior described in the execution plan.

Affected files:

- `source/WindForceView.mc`
- `source/DisplayRenderer.mc`

### 3. Proxy slot selection can jump the “current” slot into the future

Severity: Medium

`proxy/src/met-eireann.ts` keeps the most recent hourly forecast entry so slot `0` can represent current conditions, but `proxy/src/index.ts` selects the entry closest to `Date.now() + offset`. After roughly the half-hour mark, the next hourly forecast becomes closer than the current hour entry, so slot `0` can advance early into the future.

The same issue affects later offsets. This contradicts the intended behavior where the current slot should represent current conditions and later slots should align with configured hour offsets rather than whichever entry is nearest at the current minute.

Affected files:

- `proxy/src/index.ts`
- `proxy/src/met-eireann.ts`

### 4. Strict Monkey C validation regressed after the Milestone 4 rework

Severity: Low

A normal release build succeeds, but a strict build with `-l 3` fails with multiple type/scope errors in the current watch-side code, including `StorageManager`, `WindForceApp`, and `WindForceServiceDelegate`.

If `-l 3` is still part of the project’s expected validation standard, this is a regression even though the default release build currently passes.

Affected files:

- `source/StorageManager.mc`
- `source/WindForceApp.mc`
- `source/WindForceServiceDelegate.mc`

## Assumptions

- This review assumes the intended startup behavior is to show no data until GPS is acquired, based on the execution plan and the existing `NO GPS` rendering path.
- If showing last-session cached data before first fix is deliberate, finding 2 should be downgraded or reframed as a product decision.

## Verification Performed

- Reviewed the current watch-side files:
  - `source/WindForceApp.mc`
  - `source/WindForceView.mc`
  - `source/WindForceServiceDelegate.mc`
  - `source/FetchManager.mc`
  - `source/StorageManager.mc`
  - `source/DisplayRenderer.mc`
- Reviewed the current proxy files:
  - `proxy/src/index.ts`
  - `proxy/src/met-eireann.ts`
  - `proxy/src/types.ts`
- Ran `npm run typecheck` in `proxy/`
  - Result: passed
- Ran release build:
  - `monkeyc -d instinct2x -f monkey.jungle -r -o bin\review_m4_no_l3.prg -y %USERPROFILE%\.ssh\developer_key`
  - Result: `BUILD SUCCESSFUL`
- Ran strict release build:
  - `monkeyc -d instinct2x -f monkey.jungle -l 3 -r -o bin\review_m4.prg -y %USERPROFILE%\.ssh\developer_key`
  - Result: failed with multiple type/scope errors in the current Monkey C code
