# Code Review v5

Date: 2026-03-14
Reviewer: Codex
Scope: Re-review of the Milestone 4 watch-side implementation after replacing shared look-ahead callback state with per-request `LookAheadCallback` instances.

## Result

The new `LookAheadCallback` class addresses the previous look-ahead correlation bug: the callback now captures coordinates immutably at dispatch time, so I did not find a remaining issue in that path.

I found one separate concurrency defect in the model-status refresh flow.

## Findings

### 1. Medium: a newer model run can still be missed when `/model-status` and `/forecast` are started in the same compute cycle

`executeFetchCycle()` starts the lightweight `/model-status` request and then, in the same pass, can immediately start a full forecast fetch:

- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L75)
- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L78)
- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L106)
- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L113)

If `/model-status` returns first with a newer run, `onModelStatus()` forces a refetch by resetting `_lastFetchTime`:

- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L137)
- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L144)

But if the already-in-flight current-position forecast returns afterward, `onForecastReceived()` overwrites `_lastFetchTime` with `Time.now()` and commits the fetch as successful:

- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L149)
- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L157)

That matters because the proxy's `/forecast` path can legally return data from the previous model run until `latest_model_run` in KV has been updated. It reads `latest_model_run` first, builds the cache key from that value, and will return cached raw forecast data immediately when present:

- [proxy/src/index.ts](c:/Users/alex/repos/garmin_df_wind_force/proxy/src/index.ts#L177)
- [proxy/src/index.ts](c:/Users/alex/repos/garmin_df_wind_force/proxy/src/index.ts#L186)
- [proxy/src/index.ts](c:/Users/alex/repos/garmin_df_wind_force/proxy/src/index.ts#L190)
- [proxy/src/index.ts](c:/Users/alex/repos/garmin_df_wind_force/proxy/src/index.ts#L192)

So there is a real race window where:

1. the watch starts `/model-status` and `/forecast` together,
2. `/model-status` learns a newer run and sets `_lastFetchTime = 0`,
3. the in-flight `/forecast` completes with data tied to the old cached model run,
4. `onForecastReceived()` clears the forced-refetch state by writing a fresh `_lastFetchTime`.

The requirements explicitly treat model-run change as a fetch trigger for current position plus look-ahead points:

- [docs/REQUIREMENTS.md](c:/Users/alex/repos/garmin_df_wind_force/docs/REQUIREMENTS.md#L157)
- [docs/REQUIREMENTS.md](c:/Users/alex/repos/garmin_df_wind_force/docs/REQUIREMENTS.md#L168)

This finding is partly an inference from the interaction between the watch code and proxy cache behavior, but the race is credible from the current implementation.

## Verification Performed

- Read and reviewed:
  - `source/FetchManager.mc`
  - `source/LookAheadCallback.mc`
  - `source/WindForceView.mc`
  - `source/StorageManager.mc`
  - `source/ForecastService.mc`
  - `proxy/src/index.ts`
- Ran a local release build:
  - `monkeyc.bat -d instinct2x -f monkey.jungle -r -o bin\review_v6.prg -y %USERPROFILE%\.ssh\developer_key`
  - Result: `BUILD SUCCESSFUL`
  - Output size: `12,460` bytes (`~12.2 KB`)
- I did not run the Connect IQ simulator during this review
