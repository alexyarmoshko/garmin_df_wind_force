# Garmin DataField Wind Force - Code Review v16 (Dead & Repeated Code)

## Executive Summary
This third code review specifically targets **dead code** (empty methods, unreachable paths) and **repeated code** (duplicated logic, redundant execution patterns) to further streamline the application.

---

## 1. Dead Code

### Empty Initialization Stubs
**Issue:**  
There are a couple of empty method stubs that do not perform any operations or establish any state:
- `FetchManager.initialize()` is completely empty. Since it does not inherit from a class requiring a `super()` constructor, this method is dead code.
- `WindForceApp.onStart(state as Dictionary?)` is also an empty block. While this is standard Garmin AppBase boilerplate, Monkey C does not strictly demand an override if it isn't used.

**Recommendation:**  
Remove both of these empty methods to clean up the source files.

---

## 2. Repeated & Redundant Code

### [High] Redundant Flash Storage Writes in `FetchManager`
**Issue:**  
`FetchManager.updatePosition()` is called inside `compute()` once every second when the DataField is active. Inside this method:
```monkeyc
Storage.setValue("bg_lat", currentLatDeg);
Storage.setValue("bg_lon", currentLonDeg);
```
These lines write the GPS coordinates to the `.str` cache file **every single second**.
Because the background service (`WindForceServiceDelegate`) only runs globally once every 5 minutes, 299 out of 300 of these storage writes are entirely redundant operations executing the exact same coordinates to disk.

**Recommendation:**  
Wrap these `Storage.setValue()` commands in a conditional guard. For example, only execute the `setValue` if `Math.abs(currentLatDeg - previousLatDeg) > 0.001` (i.e. if the user has moved > 100 meters), or throttle the save function so it only persists memory occasionally.

### [Medium] Duplicated Staleness Mathematical Logic
**Issue:**  
In `WindForceView.onUpdate()`, the code calculates whether the data is stale:
```monkeyc
var isStale = (ts > 0 && (Time.now().value() - ts) > STALE_THRESHOLD_SEC);
```
It then passes the raw `ts` variable into `DisplayRenderer.formatLayout(..., ts, ...)`. However, `formatLayout` *re-calculates* the exact same formula internally:
```monkeyc
if (fetchTimestamp > 0) {
    var age = Time.now().value() - fetchTimestamp;
    if (age > STALE_THRESHOLD_SEC) { result = sStalePrefix; }
}
```

**Recommendation:**  
Remove the duplicate time-math logic from `DisplayRenderer.mc`. Change the `formatLayout` signature to accept a boolean `isStale` instead of `fetchTimestamp as Number`, and have the View pass the boolean directly.

### [Medium] Duplicated Layout Measurement Checks
**Issue:**  
The methods `selectBuiltInFontSize()` and `selectCustomFontSize()` loop through the fonts and execute `if (dc.getTextWidthInPixels(text, font) <= maxWidth)` to pick the largest fitting font. If no fonts fit perfectly, it returns the *smallest* font anyway as a fallback.
However, back up in `WindForceView.onUpdate()`, the outer loop executes the exact same check against the returned font:
```monkeyc
font = selectFontSize(dc, text, useCustomFontFamily);
if (dc.getTextWidthInPixels(text, font) <= maxWidth) { break; }
```
If the fallback smallest font was returned, this causes the exact same layout measurement for the smallest string to be executed **twice**.

**Recommendation:**  
You can either have `selectFontSize` return `null` if the text doesn't fit the smallest font (triggering the `slots--` loop without re-measurement), or allow the View to blindly trust the returned boolean from a redesigned sizing module.

### [Low] Redundant Settings Validation Logic
**Issue:**  
In `WindForceApp.mc`, the method `_validateIntervals()` explicitly validates and permanently corrects invalid settings at the property source (overriding `forecastInterval2` so it is strictly `> forecastInterval1`).
Because the properties are physically corrected on `onSettingsChanged`, `SettingsHelper.getSlotsString()` does not need to duplicate this safety net dynamically (`if (i2 <= i1) { i2 = i1 + 1; }`). 

**Recommendation:**  
Since `_validateIntervals()` serves as the definitive gatekeeper, the secondary fallback logic inside `SettingsHelper.getSlotsString()` is technically redundant pseudo-dead code. It can be safely removed, simplifying the helper.
