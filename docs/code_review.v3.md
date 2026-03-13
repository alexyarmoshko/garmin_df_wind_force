# Code Review v4

Date: 2026-03-13
Reviewer: Codex
Scope: Re-review of the Milestone 4 watch-side implementation after the fixes described for the previous code review findings.

## Result

The three previously reported issues are materially addressed in the current revision:

- current-position fetch state is now committed only on HTTP 200
- view lookup is now position-aware and uses exact-then-nearest cache lookup
- look-ahead forecasts now flow through `StorageManager.storeForecast()`

I found one remaining defect.

## Findings

### 1. Medium: look-ahead forecasts can still be stored under the wrong coordinates because callback-to-request matching relies on FIFO completion order

The new look-ahead implementation queues coordinates locally and then fires two asynchronous requests:

- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L122)
- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L129)
- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L130)

When a response arrives, `onLookAheadReceived()` always pops the first queued coordinate pair, regardless of which request actually completed:

- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L171)
- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L174)
- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L176)
- [source/FetchManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/FetchManager.mc#L182)

`Communications.makeWebRequest()` is asynchronous, and the SDK request options support a `:context` object specifically so callers can correlate a response with the originating request:

- [source/ForecastService.mc](c:/Users/alex/repos/garmin_df_wind_force/source/ForecastService.mc#L29)
- [BulkDownloadRequestDelegate.mc](c:/Users/alex/AppData/Roaming/Garmin/ConnectIQ/Sdks/connectiq-sdk-win-8.2.3-2025-08-11-cac5b3b21/samples/BulkDownload/source/BulkDownloadRequestDelegate.mc#L30)
- [BulkDownloadRequestDelegate.mc](c:/Users/alex/AppData/Roaming/Garmin/ConnectIQ/Sdks/connectiq-sdk-win-8.2.3-2025-08-11-cac5b3b21/samples/BulkDownload/source/BulkDownloadRequestDelegate.mc#L33)
- [BulkDownloadRequestDelegate.mc](c:/Users/alex/AppData/Roaming/Garmin/ConnectIQ/Sdks/connectiq-sdk-win-8.2.3-2025-08-11-cac5b3b21/samples/BulkDownload/source/BulkDownloadRequestDelegate.mc#L41)

I did not find any source guaranteeing in-order callback delivery. Absent that guarantee, the FIFO queue is unsafe: if the 5 km request returns before the 2.5 km request, its payload will be written under the 2.5 km rounded key, and the later response will be written under the 5 km key. That corrupts the spatial cache used by [source/StorageManager.mc](c:/Users/alex/repos/garmin_df_wind_force/source/StorageManager.mc#L55) and can make nearest-point fallback display the wrong forecast for the user’s actual position.

## Verification Performed

- Read and reviewed:
  - `source/FetchManager.mc`
  - `source/WindForceView.mc`
  - `source/StorageManager.mc`
  - `source/ForecastService.mc`
  - `docs/code_review.v2.md`
- Ran a local release build:
  - `monkeyc.bat -d instinct2x -f monkey.jungle -r -o bin\review_v4.prg -y %USERPROFILE%\.ssh\developer_key`
  - Result: `BUILD SUCCESSFUL`
  - Output size: `12,380` bytes (`~12.1 KB`)
- I did not run the Connect IQ simulator during this review
