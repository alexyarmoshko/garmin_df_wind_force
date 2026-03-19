# Garmin DataField Wind Force - Code Review v14

## Executive Summary
This review focuses on the overarching correctness, optimization (battery and performance), and maintainability of the Garmin DataField `"Wind Force"` application. 
The codebase demonstrates solid Connect IQ background event handling and good separation of concerns, but reveals some significant performance issues in the high-frequency UI update loop.

---

## 1. Optimization (Performance & Battery Life)

### [High] Frequent Storage & Property Access in `onUpdate()`
**Issue:** `WindForceView.onUpdate(dc)` is called once every second when the DataField is active on the screen. Inside this method:
- `Application.Properties.getValue("windDirection")` is invoked.
- `findBestForecast()` is called, which invokes `StorageManager.loadForecast()` or `loadNearestForecast()`.
- `loadNearestForecast()` iterates through stored keys, unpacks values, and reads from `Storage.getValue()` repeatedly.

**Impact:** Accessing the `Storage` and `Properties` modules is relatively slow and resource-intensive in Connect IQ. Doing this every second will cause noticeable sluggishness on older devices and unnecessary battery drain on all devices.

**Recommendation:** Cache the `windDirection` property and the `bestForecast` dictionary as member variables in the `WindForceView` class. 
- Re-read `windDirection` only when `onSettingsChanged()` is called or when the view is initialized.
- Re-evaluate the `bestForecast` cache only when:
  1. The device coordinates change significantly in `compute()`.
  2. New data arrives via `onBackgroundData()`.
  3. The session is reset.

### [Medium] Frequent Object Allocation in the Layout Rendering Loop
**Issue:** Also inside `WindForceView.onUpdate(dc)`, the `while (slots > 0)` loop calls `parseForecastEntries(dict, slots)` continuously to determine the layout width.
`parseForecastEntries` allocates new `Array` and `WindData` objects every time it is called.

**Impact:** Allocating multiple objects on every 1-second tick increases garbage collection pressure, leading to memory fragmentation and micro-stutters.

**Recommendation:** Parse the raw `Dictionary` into a cached `Array<WindData>` **once** whenever the `bestForecast` data changes. Then, in the `onUpdate()` layout loop, simply slice or iterate over this pre-parsed array without instantiating new `WindData` objects. You can also cache the resulting layout `text` and `font` so they are not recomputed unless the data, slots, or GPS state actually changes.

---

## 2. Maintainability

### [Medium] Duplicated Settings Parsing
**Issue:** The methods `getUnitsString()` and `getSlotsString()` are effectively duplicated across `WindForceApp.mc` and `WindForceServiceDelegate.mc`. 

**Impact:** If the logic for formatting these string parameters changes, developers will need to remember to update it in two separate places, increasing the chance of API mismatch warnings/rejections in `onBackgroundData()`.

**Recommendation:** Create a shared module (e.g., `module SettingsHelper`) marked with the `(:background)` annotation. Move the duplicated logic for `getUnitsString()` and `getSlotsString()` into this helper so both the foreground app and background delegate can access the single source of truth without violating background memory restrictions.
