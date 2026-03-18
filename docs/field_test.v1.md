# Field Test v1

## Context

This note records an on-device field test issue observed during outdoor use of the watch app, along with the code-based explanation of the current behaviour and the proposed ways to improve it.

Date recorded: 2026-03-17

## Observed Problem

During outdoor testing, the data field showed `---` for a long time.

This continued even after:

- stopping and restarting the activity
- manually waiting for GPS to lock on the current location

The key question was:

What actually triggers the forecast request and the screen update?

## Current Behaviour

### What `---` means

In the current implementation:

- `NO GPS` means there is no valid GPS position
- `---` means GPS is available, but there is no cached forecast yet for the current or nearest rounded grid point

This behaviour is defined in `DisplayRenderer.formatLayout()`.

Relevant code:

- `source/DisplayRenderer.mc`
- `source/WindForceView.mc`

### What happens in the foreground

The foreground data field does not perform HTTP requests.

`WindForceView.compute()` calls `FetchManager.updatePosition(info)`, which only:

- reads `Activity.Info.currentLocation`
- converts it to degrees
- stores `bg_lat` and `bg_lon` in `Application.Storage`

It does not trigger a web request.

Relevant code:

- `source/WindForceView.mc`
- `source/FetchManager.mc`

### What actually triggers the HTTP request

The HTTP request is currently initiated only by the background service temporal event.

`WindForceApp.getInitialView()` registers:

```monkeyc
Background.registerForTemporalEvent(new Time.Duration(5 * 60));
```

When the temporal background event fires, `WindForceServiceDelegate.onTemporalEvent()`:

1. reads `bg_lat` and `bg_lon` from storage
2. builds the `/v1/forecast` request
3. calls `Communications.makeWebRequest(...)`

Relevant code:

- `source/WindForceApp.mc`
- `source/WindForceServiceDelegate.mc`

### What updates the screen

When the background request succeeds, `WindForceApp.onBackgroundData()`:

1. validates the response against current settings
2. stores the forecast under the rounded coordinate key
3. calls `WatchUi.requestUpdate()`

That redraw is what updates the field from `---` to forecast text.

If the background request fails, the app still requests a redraw, but no forecast is stored, so the display can remain `---`.

Relevant code:

- `source/WindForceApp.mc`
- `source/StorageManager.mc`

## Why The Field Test Behaved Like That

The test result is consistent with the current architecture:

- GPS lock does not trigger a fetch
- activity start does not trigger a fetch
- activity stop does not trigger a fetch
- stop/start can actually reset the background temporal registration, rather than forcing an immediate forecast request

So the likely sequence was:

1. the field acquired GPS and moved from `NO GPS` state into `---`
2. no forecast was cached yet
3. no immediate request was triggered by that GPS transition
4. the app then had to wait for the background temporal event
5. if that background request failed or had not yet fired, the display stayed `---`

## Available Background Triggers Besides Temporal

The Garmin background service API offers these additional triggers:

- `Background.registerForActivityCompletedEvent()` -> `ServiceDelegate.onActivityCompleted(activity)`
- `Background.registerForGoalEvent(goalType)` -> `ServiceDelegate.onGoalReached(goalType)`
- `Background.registerForStepsEvent()` -> `ServiceDelegate.onSteps()`
- `Background.registerForSleepEvent()` -> `ServiceDelegate.onSleepTime()`
- `Background.registerForWakeEvent()` -> `ServiceDelegate.onWakeTime()`
- `Background.registerForPhoneAppMessageEvent()` -> `ServiceDelegate.onPhoneAppMessage(msg)`
- `Background.registerForOAuthResponseEvent()` -> `ServiceDelegate.onOAuthResponse()`
- `Background.registerForAppInstallStateEvent()` -> `ServiceDelegate.onAppInstallStateEvent(event)` in SDK metadata for Connect IQ 5.0.0+

These are valid background-service entry points, and Garmin documents that a callback inside `System.ServiceDelegate` can initiate system events such as `Communications`.

However, none of these are a direct trigger for:

- first GPS fix
- location change
- activity start

For this app, they do not provide a clean substitute for "fetch immediately when the watch first gets a usable position."

## Proposed Solutions

### Option 1: Schedule an immediate temporal event on first valid GPS fix

This is the most relevant solution for the observed field-test problem.

When the app transitions from:

- no position

to:

- valid GPS position

the foreground app can register a one-shot temporal event for `Time.now()` instead of waiting for the normal repeating interval.

This would cause the background service to run as soon as Garmin allows.

After that first fetch, the app can continue with the normal repeating 5-minute schedule.

### Important Garmin constraint

`Background.registerForTemporalEvent(Time.now())` does not mean "always run instantly".

Garmin's rule is:

- if a temporal event is scheduled for a time in the past, it fires immediately
- but temporal events cannot be scheduled less than 5 minutes after the last temporal event

So the safe pattern is:

```monkeyc
using Toybox.Background;
using Toybox.Time;

const FIVE_MINUTES = new Time.Duration(5 * 60);

var lastTime = Background.getLastTemporalEventTime();
if (lastTime != null) {
    Background.registerForTemporalEvent(lastTime.add(FIVE_MINUTES));
} else {
    Background.registerForTemporalEvent(Time.now());
}
```

Practical meaning:

- if no temporal event has fired recently, the request can happen immediately
- if the last temporal event was under 5 minutes ago, the app must schedule the earliest legal time instead

### Option 2: Use phone-app messages as an explicit push trigger

The app could register for phone app messages and trigger a background request when a paired phone-side component decides conditions are right.

This is technically possible, but it is a much larger architecture change because it requires a phone companion integration and its own trigger logic.

For the current problem, this is likely excessive.

### Option 3: Keep the current pure 5-minute polling model

This is the current implementation.

It is simple and reliable from an architecture perspective, but it has the UX drawback observed during field testing:

- after GPS becomes valid, the user may still wait up to the next allowed temporal event before seeing any forecast

## Recommended Next Step

The recommended change is:

Implement Option 1 so that the first valid GPS fix schedules an immediate temporal event using `Time.now()` when legal, or the earliest allowed time derived from `Background.getLastTemporalEventTime()` when a recent temporal event has already run.

That directly addresses the field-test issue without introducing a phone companion or unrelated trigger types.

## References

Code references:

- `source/WindForceView.mc`
- `source/FetchManager.mc`
- `source/WindForceApp.mc`
- `source/WindForceServiceDelegate.mc`
- `source/DisplayRenderer.mc`
- `source/StorageManager.mc`

Garmin SDK references used in analysis:

- `Toybox.Background.registerForTemporalEvent()`
- `Toybox.System.ServiceDelegate`
- `Toybox.Application.AppBase.onBackgroundData()`
