# Code Review v5

Date: 2026-03-13
Reviewer: Codex
Scope: Re-review of the Milestone 4 watch-side implementation after replacing the FIFO look-ahead queue with dedicated coordinate slots and separate callbacks.

## Result

The new callback split fixes the earlier within-cycle FIFO ordering problem. I found one remaining race.

## Findings

### 1. Medium: look-ahead responses can still be written to the wrong coordinates because the coordinate slots are shared across fetch cycles

The new implementation stores look-ahead coordinates in four mutable instance fields:

- [source/FetchManager.mc](~/repos/garmin_df_wind_force/source/FetchManager.mc#L33)
- [source/FetchManager.mc](~/repos/garmin_df_wind_force/source/FetchManager.mc#L37)

Each fetch cycle overwrites those fields before dispatching the asynchronous look-ahead requests:

- [source/FetchManager.mc](~/repos/garmin_df_wind_force/source/FetchManager.mc#L121)
- [source/FetchManager.mc](~/repos/garmin_df_wind_force/source/FetchManager.mc#L128)
- [source/FetchManager.mc](~/repos/garmin_df_wind_force/source/FetchManager.mc#L135)

But the callbacks later store responses using whatever values those shared fields hold at callback time:

- [source/FetchManager.mc](~/repos/garmin_df_wind_force/source/FetchManager.mc#L176)
- [source/FetchManager.mc](~/repos/garmin_df_wind_force/source/FetchManager.mc#L178)
- [source/FetchManager.mc](~/repos/garmin_df_wind_force/source/FetchManager.mc#L185)
- [source/FetchManager.mc](~/repos/garmin_df_wind_force/source/FetchManager.mc#L187)

`_fetchInProgress` only guards the current-position request, and it is cleared as soon as `onForecastReceived()` runs:

- [source/FetchManager.mc](~/repos/garmin_df_wind_force/source/FetchManager.mc#L41)
- [source/FetchManager.mc](~/repos/garmin_df_wind_force/source/FetchManager.mc#L58)
- [source/FetchManager.mc](~/repos/garmin_df_wind_force/source/FetchManager.mc#L154)
- [source/FetchManager.mc](~/repos/garmin_df_wind_force/source/FetchManager.mc#L172)

That means a later fetch cycle can start and overwrite `_la1*` / `_la2*` while older look-ahead requests are still in flight. The failure path makes this particularly plausible: current-position retries now happen immediately after a failed request, but any already-dispatched look-ahead responses can still arrive afterward. When that happens, the old response is stored under the newer cycle's coordinates, corrupting the spatial cache.

This is an inference from the asynchronous request model: I did not find any code here that ties a look-ahead response to an immutable per-request coordinate payload.

## Verification Performed

- Read and reviewed:
  - `source/FetchManager.mc`
  - `source/WindForceView.mc`
  - `source/StorageManager.mc`
  - `source/ForecastService.mc`
- Ran a local release build:
  - `monkeyc.bat -d instinct2x -f monkey.jungle -r -o bin\review_v5.prg -y %USERPROFILE%\.ssh\developer_key`
  - Result: `BUILD SUCCESSFUL`
  - Output size: `12,572` bytes (`~12.3 KB`)
- I did not run the Connect IQ simulator during this review
