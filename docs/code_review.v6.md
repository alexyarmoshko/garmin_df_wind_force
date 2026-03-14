# Code Review v6

Date: 2026-03-14
Reviewer: Codex
Scope: Re-review of the Milestone 4 watch-side implementation after adding stale-model-run detection in `onForecastReceived()`.

## Result

The new `response.model_run` check materially fixes the previously reported `/model-status` vs `/forecast` race: if a newer model run is detected while a forecast request is in flight, the stale response is stored for display but no longer commits `_lastFetchTime`.

I found one remaining issue.

## Findings

### 1. Medium: the first successful `/model-status` response after startup still forces an unnecessary refetch even when the cached forecast already uses that same model run

`_lastModelRun` is only updated by `onModelStatus()`:

- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L33)
- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L137)
- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L142)

But `onForecastReceived()` reads `model_run` from the forecast payload without ever seeding `_lastModelRun` from it:

- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L155)
- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L159)
- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L178)

That means `_lastModelRun` still starts as `""` after app startup. On the first successful `/model-status` response, this condition always fires:

- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L141)

So the code resets `_lastFetchTime = 0` and forces another full fetch even if the just-stored forecast already came from that exact same model run. The likely user-visible effect is one redundant refetch after startup or after state reset, including redundant look-ahead requests on the initial cycle when heading is available.

This is not a correctness failure on the displayed data, but it is still unnecessary network and battery work in the core fetch loop.

## Verification Performed

- Read and reviewed:
  - `source/FetchManager.mc`
  - `source/LookAheadCallback.mc`
  - `source/ForecastService.mc`
  - `docs/code_review.v5.md`
- Ran a local release build:
  - `monkeyc.bat -d instinct2x -f monkey.jungle -r -o bin\review_v7.prg -y %USERPROFILE%\.ssh\developer_key`
  - Result: `BUILD SUCCESSFUL`
  - Output size: `12,540` bytes (`~12.3 KB`)
- I did not run the Connect IQ simulator during this review
