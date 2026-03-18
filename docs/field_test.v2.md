# Field Test v2

## Context

This note records the follow-up analysis for forecast cache pruning at the end of an activity session.

The focus here is narrower than v1:

- the problem of stale cached forecasts surviving across activities
- why the current implementation does not clear them on activity completion
- the two candidate hooks discussed for pruning:
  - `System.ServiceDelegate.onActivityCompleted(activity)`
  - `WatchUi.DataField.onTimerReset()`

Date recorded: 2026-03-18

## Observed Problem

The app keeps forecast data in on-watch storage across activity sessions unless a settings change clears it or the cache is naturally overwritten/pruned by location count.

That creates a session-boundary problem:

- a new kayaking activity can start with cached forecasts from the previous activity still present
- the field can therefore show stale but locally valid forecast data from the last session
- there is currently no explicit "activity finished, clear session forecast state" step

The design question was:

What is the correct trigger to prune forecast cache when an activity ends?

## Current Behaviour

### How forecast cache is stored

Forecast responses are stored in `Application.Storage` under rounded-location keys managed by `StorageManager`.

Current cache behaviour:

- full cache clear happens on settings change via `StorageManager.clearAllForecasts()`
- a forecast for the same rounded location is overwritten by a newer one
- older cached locations are pruned only when the cache exceeds the location-count limit

There is no dedicated cache clear on activity completion.

Relevant code:

- `source/StorageManager.mc`
- `source/WindForceApp.mc`

### Why stale session data can survive

The app currently treats the forecast cache as general persisted storage, not as activity-scoped state.

As a result:

- ending an activity does not clear cached forecasts
- stopping the app does not currently clear cached forecasts
- starting the next activity can reuse prior forecast data if the rounded location still matches

This is useful for persistence, but incorrect if the product intent is "each activity should start clean."

## Explanation Of The Two Candidate Triggers

### Option 1: `ServiceDelegate.onActivityCompleted(activity)`

This is the background-service callback specifically documented for completed activities.

Why it fits:

- it is semantically tied to activity completion
- it does not depend on the foreground data field still being active
- it is the cleanest session-boundary hook Garmin exposes for this use case

Expected use:

1. register `Background.registerForActivityCompletedEvent()`
2. implement `onActivityCompleted(activity)` in the service delegate
3. clear forecast cache and related request-state keys there

Important limitation:

Garmin documents this as firing when an activity is "completed", but does not clearly spell out every save/discard edge case in the API text used for this analysis. It should be treated as the best completion-aligned hook, but still verified on the target device.

### Option 2: `WatchUi.DataField.onTimerReset()`

This is the data-field callback documented for when the current activity has ended and the timer is reset.

Why it fits:

- it is activity-end related rather than generic app shutdown
- it runs in the foreground data-field lifecycle
- it gives the field a direct place to clear session state when the activity concludes

Important limitation:

This is a foreground/UI callback. If the data field is not active in the way you expect at completion time, it is less robust than the background completion event.

## Why `AppBase.onStop()` Is Not The Preferred Solution

`Application.AppBase.onStop()` is an application termination/suspension callback, not a dedicated activity-completed callback.

That makes it the wrong primary signal for cache pruning:

- it is broader than the business event you actually care about
- it can run because the app is exiting or being suspended, not because the activity truly completed
- tying forecast deletion to generic app stop risks clearing cache in cases unrelated to the end of a session

For that reason, the proposed solution set for this note is intentionally limited to:

- `onActivityCompleted(activity)`
- `onTimerReset()`

## Proposed Solution

### Preferred solution

Use `ServiceDelegate.onActivityCompleted(activity)` as the canonical cache-pruning trigger.

This gives the pruning logic the correct meaning:

- clear cached forecasts when the activity is completed
- do not rely on app shutdown semantics
- keep session cleanup aligned with the Garmin background event designed for completed activities

Recommended cleanup scope:

- all `fc_*` forecast entries
- `fc_keys`
- `bg_lat`
- `bg_lon`
- optional request-shaping keys such as rounded coordinates or settings-derived request markers if they are being persisted for the session

### Secondary safety net

Also implement pruning in `WatchUi.DataField.onTimerReset()`.

This gives a foreground safety net:

- if the field is active at activity end, session data is cleared immediately from the UI-side lifecycle
- if the background completion event is delayed, unavailable, or behaves differently than expected on a specific device/activity flow, the field still has a cleanup path

### Practical recommendation

Use both, with different roles:

- `onActivityCompleted(activity)` as the primary and authoritative activity-completion hook
- `onTimerReset()` as a foreground backup aligned with the end of the timer/activity

That combination is more defensible than relying on `onStop()`.

## Recommendation Summary

The recommended implementation plan is:

1. register for activity completed background events
2. clear forecast cache in `ServiceDelegate.onActivityCompleted(activity)`
3. add matching cleanup in `WatchUi.DataField.onTimerReset()` as a safety net
4. do not use `AppBase.onStop()` as the main cache-pruning mechanism

This keeps pruning tied to the actual end of an activity instead of generic app shutdown.

## References

Code references:

- `source/StorageManager.mc`
- `source/WindForceApp.mc`
- `source/WindForceServiceDelegate.mc`
- `source/WindForceView.mc`

Garmin SDK references used in analysis:

- `Toybox.System.ServiceDelegate.onActivityCompleted()`
- `Toybox.Background.registerForActivityCompletedEvent()`
- `Toybox.WatchUi.DataField.onTimerReset()`
- `Toybox.Application.AppBase.onStop()`
