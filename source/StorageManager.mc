import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Math;

// Maximum number of cached forecast grid points
const MAX_CACHED_FORECASTS = 5;

module StorageManager {

    //! Store a forecast response dictionary keyed by rounded coordinates.
    //! @param roundedLat Latitude rounded to 0.025 degrees
    //! @param roundedLon Longitude rounded to 0.025 degrees
    //! @param data The forecast response dictionary from the proxy
    (:typecheck(false))
    function storeForecast(
        roundedLat as String,
        roundedLon as String,
        data as Dictionary
    ) as Void {
        var key = "fc_" + roundedLat + "_" + roundedLon;
        Storage.setValue(key, data);

        // Track stored keys for pruning
        var keys = getStoredKeys();
        // Remove if already present (will re-add at end)
        var newKeys = [] as Array<String>;
        for (var i = 0; i < keys.size(); i++) {
            if (!keys[i].equals(key)) {
                newKeys.add(keys[i]);
            }
        }
        newKeys.add(key);
        Storage.setValue("fc_keys", newKeys);

        pruneStorage();
    }

    //! Load a forecast for exact rounded coordinates.
    //! @return The forecast dictionary or null if not cached
    (:typecheck(false))
    function loadForecast(
        roundedLat as String,
        roundedLon as String
    ) as Dictionary? {
        var key = "fc_" + roundedLat + "_" + roundedLon;
        var val = Storage.getValue(key);
        if (val instanceof Dictionary) {
            return val;
        }
        return null;
    }

    //! Find the nearest cached forecast within 2.5 km of the given position.
    //! @param latDeg Latitude in degrees
    //! @param lonDeg Longitude in degrees
    //! @return The forecast dictionary or null if none within range
    function loadNearestForecast(latDeg as Double, lonDeg as Double) as Dictionary? {
        var keys = getStoredKeys();
        var bestData = null;
        var bestDist = 999999.0;

        for (var i = 0; i < keys.size(); i++) {
            var parts = splitFcKey(keys[i]);
            if (parts == null) {
                continue;
            }
            var klat = (parts[0] as String).toDouble();
            var klon = (parts[1] as String).toDouble();
            if (klat == null || klon == null) {
                continue;
            }
            var dist = approxDistKm(latDeg, lonDeg, klat, klon);
            if (dist < bestDist) {
                bestDist = dist;
                var val = Storage.getValue(keys[i]);
                if (val instanceof Dictionary) {
                    bestData = val;
                }
            }
        }

        if (bestDist <= 2.5) {
            return bestData;
        }
        return null;
    }

    //! Clear all cached forecasts (e.g., after settings change).
    (:typecheck(false))
    function clearAllForecasts() as Void {
        var keys = getStoredKeys();
        for (var i = 0; i < keys.size(); i++) {
            Storage.deleteValue(keys[i]);
        }
        Storage.setValue("fc_keys", [] as Array<String>);
    }

    //! Remove old entries, keeping only the most recent MAX_CACHED_FORECASTS.
    (:typecheck(false))
    function pruneStorage() as Void {
        var keys = getStoredKeys();
        if (keys.size() <= MAX_CACHED_FORECASTS) {
            return;
        }
        // Keys are ordered oldest-first; remove from the front
        var toRemove = keys.size() - MAX_CACHED_FORECASTS;
        for (var i = 0; i < toRemove; i++) {
            Storage.deleteValue(keys[i]);
        }
        var remaining = keys.slice(toRemove, null);
        Storage.setValue("fc_keys", remaining);
    }

    //! Get the list of stored forecast keys.
    (:typecheck(false))
    function getStoredKeys() as Array<String> {
        var val = Storage.getValue("fc_keys");
        if (val instanceof Array) {
            return val;
        }
        return [] as Array<String>;
    }

    //! Round a coordinate value to the nearest 0.025 degrees (matching proxy).
    //! @param value Coordinate in degrees
    //! @return Rounded value as a 3-decimal-place string
    function roundCoord(value as Double) as String {
        var rounded = Math.round(value / 0.025).toDouble() * 0.025;
        return rounded.format("%.3f");
    }

    //! Parse a forecast key "fc_{lat}_{lon}" into [lat, lon] strings.
    //! Returns null if the key format is invalid.
    function splitFcKey(key as String) as Array<String>? {
        // Key format: "fc_53.350_-6.250"
        // Skip "fc_" prefix (3 chars), then split on "_"
        if (key.length() < 4) {
            return null;
        }
        var rest = key.substring(3, key.length());
        if (rest == null) {
            return null;
        }
        // Find the separator "_" between lat and lon
        // Lat can be negative, so we need to find the underscore after the lat value
        // Strategy: find "_" that is preceded by a digit (not the first char)
        var sepIdx = -1;
        for (var i = 1; i < (rest as String).length(); i++) {
            var ch = (rest as String).substring(i, i + 1);
            if (ch != null && (ch as String).equals("_")) {
                sepIdx = i;
                break;
            }
        }
        if (sepIdx < 0) {
            return null;
        }
        var lat = (rest as String).substring(0, sepIdx);
        var lon = (rest as String).substring(sepIdx + 1, (rest as String).length());
        if (lat == null || lon == null) {
            return null;
        }
        return [lat as String, lon as String] as Array<String>;
    }

    //! Approximate distance in km between two points given in degrees.
    //! Uses equirectangular approximation (accurate enough for <5 km).
    function approxDistKm(
        lat1 as Double, lon1 as Double,
        lat2 as Double, lon2 as Double
    ) as Double {
        var toRad = Math.PI / 180.0;
        var dLat = (lat2 - lat1) * toRad;
        var dLon = (lon2 - lon1) * toRad;
        var midLat = (lat1 + lat2) / 2.0 * toRad;
        var dx = dLon * Math.cos(midLat);
        var R = 6371.0;
        return (Math.sqrt(dx * dx + dLat * dLat) * R).toDouble();
    }

}
