# Code Review v3

Date: 2026-03-13
Reviewer: Codex
Scope: Milestone 4 implementation currently present in the repository, with emphasis on the Garmin watch communication layer, fetch strategy, storage, and rendering path.

## Findings

### 1. High: failed forecast requests are recorded as successful fetches, which suppresses retries after transient network errors

In [source/FetchManager.mc:86](~/repos/garmin_df_wind_force/source/FetchManager.mc#L86), the fetch state is advanced before the HTTP response has succeeded:

- [source/FetchManager.mc:86](~/repos/garmin_df_wind_force/source/FetchManager.mc#L86)
- [source/FetchManager.mc:92](~/repos/garmin_df_wind_force/source/FetchManager.mc#L92)
- [source/FetchManager.mc:94](~/repos/garmin_df_wind_force/source/FetchManager.mc#L94)
- [source/FetchManager.mc:95](~/repos/garmin_df_wind_force/source/FetchManager.mc#L95)

But the success callback only persists data when the response is `200` and otherwise just clears `_fetchInProgress`:

- [source/FetchManager.mc:125](~/repos/garmin_df_wind_force/source/FetchManager.mc#L125)
- [source/FetchManager.mc:127](~/repos/garmin_df_wind_force/source/FetchManager.mc#L127)
- [source/FetchManager.mc:134](~/repos/garmin_df_wind_force/source/FetchManager.mc#L134)

The milestone contract and requirements both define the time trigger relative to the last successful fetch, not the last attempted fetch:

- [docs/execution_plan.md:368](~/repos/garmin_df_wind_force/docs/execution_plan.md#L368)
- [docs/execution_plan.md:372](~/repos/garmin_df_wind_force/docs/execution_plan.md#L372)
- [docs/REQUIREMENTS.md:156](~/repos/garmin_df_wind_force/docs/REQUIREMENTS.md#L156)

As implemented, a dropped phone connection or transient proxy failure can leave the field stuck on old cached data for up to 30 minutes while the fetch manager believes a fresh fetch already happened. This is a functional regression in the offline/error path.

### 2. High: the renderer ignores the current position and nearest-cache lookup, so the look-ahead strategy is effectively dead

The view is supposed to read the forecast for the current position from storage, falling back to the nearest cached grid point:

- [docs/execution_plan.md:391](~/repos/garmin_df_wind_force/docs/execution_plan.md#L391)
- [docs/execution_plan.md:398](~/repos/garmin_df_wind_force/docs/execution_plan.md#L398)
- [docs/REQUIREMENTS.md:208](~/repos/garmin_df_wind_force/docs/REQUIREMENTS.md#L208)
- [docs/REQUIREMENTS.md:213](~/repos/garmin_df_wind_force/docs/REQUIREMENTS.md#L213)

`StorageManager` has the right API for that:

- [source/StorageManager.mc:39](~/repos/garmin_df_wind_force/source/StorageManager.mc#L39)
- [source/StorageManager.mc:55](~/repos/garmin_df_wind_force/source/StorageManager.mc#L55)

But `WindForceView` never uses those functions. Instead, `findBestForecast()` just returns the most recently stored `fc_*` entry:

- [source/WindForceView.mc:57](~/repos/garmin_df_wind_force/source/WindForceView.mc#L57)
- [source/WindForceView.mc:98](~/repos/garmin_df_wind_force/source/WindForceView.mc#L98)
- [source/WindForceView.mc:102](~/repos/garmin_df_wind_force/source/WindForceView.mc#L102)

That means the display is not actually position-aware once data is cached. If the paddler moves into an area covered by a previously fetched look-ahead point, or moves back toward an older cached point, the field still renders whichever current-position fetch happened last. This defeats one of the main milestone 4 behaviors: spatially relevant cached fallback between network fetches.

### 3. Medium: look-ahead responses are stored under ad-hoc keys that collide, bypass pruning, and cannot be discovered by the storage lookup code

Look-ahead results are not stored through `StorageManager.storeForecast()`. They are written directly under `la_{time}`:

- [source/FetchManager.mc:140](~/repos/garmin_df_wind_force/source/FetchManager.mc#L140)
- [source/FetchManager.mc:151](~/repos/garmin_df_wind_force/source/FetchManager.mc#L151)
- [source/FetchManager.mc:153](~/repos/garmin_df_wind_force/source/FetchManager.mc#L153)

That breaks the storage design in three ways:

- the key has no coordinates, so it cannot support nearest-grid lookup
- both look-ahead points from the same cycle can overwrite each other when their first forecast slot shares the same timestamp
- pruning only tracks `fc_keys`, so `la_*` entries are invisible to [source/StorageManager.mc:86](~/repos/garmin_df_wind_force/source/StorageManager.mc#L86) and do not obey the storage-retention limit from [docs/REQUIREMENTS.md:231](~/repos/garmin_df_wind_force/docs/REQUIREMENTS.md#L231)

This leaves the app paying the network cost for look-ahead fetches without getting a usable or well-bounded cache out of them.

## Verification Performed

- Read and reviewed:
  - `source/ForecastService.mc`
  - `source/FetchManager.mc`
  - `source/StorageManager.mc`
  - `source/WindForceView.mc`
  - `source/WindForceApp.mc`
  - `source/DisplayRenderer.mc`
  - `resources/properties/properties.xml`
  - `manifest.xml`
  - `docs/REQUIREMENTS.md`
  - `docs/execution_plan.md`
  - `docs/execution_plan_changelog.md`
- Ran a local Connect IQ build:
  - `monkeyc.bat -d instinct2x -f monkey.jungle -o bin\review.prg -y %USERPROFILE%\.ssh\developer_key`
  - Result: `BUILD SUCCESSFUL`
- I did not run the Connect IQ simulator during this review
