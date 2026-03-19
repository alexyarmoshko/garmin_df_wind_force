# Garmin DataField Wind Force - Code Review v15 (Deep Dive)

## Executive Summary
This secondary "deep-dive" code review focuses on micro-optimizations, string handling efficiencies, and mitigating garbage collection pressure. While the v14 fixes resolved the major battery-drain bottlenecks, there are still several areas where string allocation and layout rendering can be further optimized to ensure peak performance on low-memory Garmin devices.

---

## 1. Optimization (Memory & CPU)

### [Medium] Substring Allocation Loop in `StorageManager.splitFcKey`
**Issue:**  
To parse the cache key (e.g., `"53.350_-6.250"`), `splitFcKey()` manually iterates character-by-character using `substring(i, i + 1)` and `.equals("_")` to locate the delimiter. 
Because MonkeyC strings are immutable, `substring(i, i + 1)` allocates a new 1-character string object in memory on *every single iteration*. This method is called repeatedly for every cached entry when determining the nearest forecast grid point.

**Recommendation:**  
Replace the manual loop with the native SDK method `String.find()`. Because the key format is strictly controlled and the negative sign `-` will only appear before the digits, a simple `var sepIdx = rest.find("_");` will locate the delimiter instantly in a single native execution, eliminating all intermediate string allocations.

### [Medium] Continual String Re-rendering in `WindForceView.onUpdate`
**Issue:**  
While object creation (`WindData`) was successfully cached in v14, the text layout logic in `onUpdate()` still relies on rapid string concatenation.  
```monkeyc
text = DisplayRenderer.formatLayout(_cachedForecasts, ts, _fetchMgr.hasPosition, slots);
```
This is executed sequentially (down-sizing slots) on every 1-second tick. `formatLayout` uses the `+` operator heavily, which in MonkeyC dynamically allocates a new concatenated string at each step.

**Recommendation:**  
The visual output of the datafield only actually changes under three conditions:
1. The available layout width changes (e.g., orientation or fields change).
2. The `_cachedForecasts` data is refreshed from the background service.
3. The data crosses the 30-minute staleness threshold (evaluating to true inside `formatLayout`).

You should cache the final `_displayText` and `_displayFont` strings as member variables in `WindForceView`. Rebuild these cached strings only when one of the three conditions above triggers.

### [Minor] Dynamic Unicode Conversion in `DisplayRenderer.dirToArrow`
**Issue:**  
When the user disables custom fonts, arrows are generated dynamically using `0x2193.toChar().toString()`. This allocates a `Char` object and a `String` object dynamically on the heap every time `formatLayout` renders a directional arrow.

**Recommendation:**  
Pre-allocate these arrows at the module level. Depending on the MonkeyC compiler version, you can simply declare them as string constants (e.g., `const ARROW_N = "\u2193";`), or instantiate them once during `init()` and store them in dictionary/variables. This prevents dynamic heap allocations during active UI rendering.

---

## 2. Maintainability

### [Low] Background Memory Headroom
**Finding:**  
The background temporal event fetches forecast JSON for the UI. The memory footprint of the parsed JSON Dictionary is currently well within the 32KB constraint for Instinct devices. 
**Note:** Ensure that the API Proxy server (kayakshaver.com) strictly limits the number of slots returned (e.g., max 6) and avoids passing large, verbose string keys. Keeping the JSON payload minimal protects against out-of-memory `Unhandled Exception` crashes in the background service space.
