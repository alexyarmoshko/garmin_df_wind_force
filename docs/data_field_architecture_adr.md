# Architecture Decision Record (ADR): Foreground & Background Process Communication

## Status
Accepted

## Context
The Garmin Connect IQ framework imposes strict memory and execution sandboxing on background processes. The `Wind Force` application operates as a DataField (`WindForceView` and `WindForceApp`) while simultaneously running a 5-minute temporal background event (`WindForceServiceDelegate`) to fetch JSON weather data.

By Garmin's design:
1. **Isolated Memory Spaces:** The active foreground DataField and the background service run in completely separate virtual machines. They do not share variables, instances, or "in-memory" state.
2. **Feature Sandboxing:** Background processes have zero access to the `Activity.Info` module. This means the background service cannot natively read the user's live GPS coordinates, heart rate, or speed, nor can it read the active `.FIT` recording file.
3. **Battery Constraints:** While the background service *could* theoretically boot up the GPS hardware to request a coordinate (`Position.enableLocationEvents`), doing so drains massive amounts of battery and often times out against the strict ~30-second background execution limit.

## Decision
We architected the application to use the watch's permanent `Application.Storage` system as a persistent "mailbox" bridge between the two isolated processes.

1. **Foreground to Background (The Mailbox):** 
   - The active DataField receives the live GPS coordinate for free every 1 second via `compute(info as Activity.Info)`.
   - The `FetchManager` evaluates the user's movement. If the user has moved significantly (e.g., a buffer of `> 0.001` degrees, equating to ~100 meters), the `FetchManager` writes the current coordinates to Flash memory (`Storage.setValue("bg_lat", ...)`).
   - This strict mathematical throttling prevents the DataField from needlessly hammering the Flash storage 1x a second.
   
2. **Background Execution:**
   - When OS allows the temporal event to wake up (every 5 minutes), `WindForceServiceDelegate` queries the `Application.Storage` mailbox to read the coordinates left by the foreground.
   - It performs the REST API call to fetch the wind forecast for that location.

3. **Background to Foreground (The Payload Exit):**
   - The background service cannot write directly into the UI state. Instead, it terminates itself by calling `Background.exit(Dictionary data)`.
   - The OS safely passes this dictionary payload across the sandbox wall, triggering the foreground app's `onBackgroundData()` callback, where the JSON is processed and cached for fast UI rendering.

## Consequences
- **Positive:** Maximum battery conservation. The GPS hardware is never unnecessarily awoken by the background service, and flash storage health is preserved via movement-throttling.
- **Positive:** Complies strictly with Garmin's memory and activity sandboxing rules, preventing out-of-memory crashes on older devices like the Instinct 2.
- **Negative:** Adds architectural complexity. Testing requires strictly simulating the 5-minute background temporal events and managing race conditions if the UI properties and background storage update out of sync. This is mitigated by explicitly passing configuration state back inside the `Background.exit()` payload for validation.
