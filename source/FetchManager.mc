import Toybox.Activity;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Time;
import Toybox.WatchUi;

// Fetch trigger constants
const DISTANCE_TRIGGER_KM = 1.5;
const TIME_TRIGGER_SEC = 1800;            // 30 minutes
const MODEL_STATUS_POLL_SEC = 900;        // 15 minutes
const LOOK_AHEAD_DIST_KM = 2.5;
const EARTH_RADIUS_KM = 6371.0;

class FetchManager {

    private var _lastFetchLatRad as Double = 0.0d;
    private var _lastFetchLonRad as Double = 0.0d;
    private var _lastFetchTime as Number = 0;
    private var _lastModelRun as String = "";
    private var _lastModelCheckTime as Number = 0;
    private var _lastFetchedUnits as String = "";
    private var _lastFetchedSlots as String = "";
    private var _fetchInProgress as Boolean = false;
    private var _slotCount as Number = 1;

    function initialize() {
    }

    //! Set the current slot count (called from WindForceView.onLayout).
    function setSlotCount(count as Number) as Void {
        _slotCount = count;
    }

    //! Main entry point, called from compute().
    function executeFetchCycle(info as Activity.Info) as Void {
        if (_fetchInProgress) {
            return;
        }

        var loc = info.currentLocation;
        if (loc == null) {
            return;
        }

        var coords = (loc as Position.Location).toRadians();
        var latRad = coords[0] as Double;
        var lonRad = coords[1] as Double;
        var now = Time.now().value();

        var units = getWindUnitsString();
        var slots = buildSlotsString();

        // Poll model status every 15 minutes
        if (now - _lastModelCheckTime > MODEL_STATUS_POLL_SEC) {
            _lastModelCheckTime = now;
            ForecastService.fetchModelStatus(method(:onModelStatus));
        }

        // Evaluate triggers
        var triggered = false;

        if (_lastFetchTime == 0) {
            triggered = true;
        } else {
            var dist = haversineKm(latRad, lonRad, _lastFetchLatRad, _lastFetchLonRad);
            if (dist > DISTANCE_TRIGGER_KM) {
                triggered = true;
            }
            if (now - _lastFetchTime > TIME_TRIGGER_SEC) {
                triggered = true;
            }
        }

        if (!units.equals(_lastFetchedUnits) || !slots.equals(_lastFetchedSlots)) {
            triggered = true;
        }

        if (!triggered) {
            return;
        }

        _fetchInProgress = true;
        var latDeg = latRad * 180.0d / Math.PI;
        var lonDeg = lonRad * 180.0d / Math.PI;

        ForecastService.fetchForecast(latDeg, lonDeg, units, slots, method(:onForecastReceived));

        _lastFetchLatRad = latRad;
        _lastFetchLonRad = lonRad;
        _lastFetchTime = now;
        _lastFetchedUnits = units;
        _lastFetchedSlots = slots;

        // Look-ahead points along current bearing
        var bearing = info.currentHeading;
        if (bearing != null) {
            var bearingD = (bearing as Float).toDouble();
            for (var i = 1; i <= 2; i++) {
                var distKm = (LOOK_AHEAD_DIST_KM * i).toDouble();
                var pt = destinationPoint(latRad, lonRad, bearingD, distKm);
                var laLatDeg = pt[0] * 180.0d / Math.PI;
                var laLonDeg = pt[1] * 180.0d / Math.PI;
                ForecastService.fetchForecast(laLatDeg, laLonDeg, units, slots, method(:onLookAheadReceived));
            }
        }
    }

    //! Callback for model status response.
    function onModelStatus(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data instanceof Dictionary) {
            var mr = (data as Dictionary)["model_run"];
            if (mr instanceof String && !mr.equals(_lastModelRun)) {
                _lastModelRun = mr;
                // Force refetch on next cycle
                _lastFetchTime = 0;
            }
        }
    }

    //! Callback for current-position forecast.
    function onForecastReceived(responseCode as Number, data as Dictionary or String or Null) as Void {
        _fetchInProgress = false;
        if (responseCode == 200 && data instanceof Dictionary) {
            var dict = data as Dictionary;
            var latDeg = _lastFetchLatRad * 180.0d / Math.PI;
            var lonDeg = _lastFetchLonRad * 180.0d / Math.PI;
            var rLat = StorageManager.roundCoord(latDeg);
            var rLon = StorageManager.roundCoord(lonDeg);
            StorageManager.storeForecast(rLat, rLon, dict);
            Storage.setValue("last_fetch_ts", Time.now().value());
        }
        WatchUi.requestUpdate();
    }

    //! Callback for look-ahead forecast (best-effort).
    function onLookAheadReceived(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data instanceof Dictionary) {
            var dict = data as Dictionary;
            // Store look-ahead data for nearest-forecast lookup
            // We derive rounded coords from the response model_run and forecasts
            // For look-aheads, store with a sequential key that loadNearestForecast can scan
            var forecasts = dict["forecasts"];
            if (forecasts instanceof Array && (forecasts as Array).size() > 0) {
                var first = (forecasts as Array)[0];
                if (first instanceof Dictionary) {
                    // Use forecast time as part of key to avoid collisions
                    var t = (first as Dictionary)["time"];
                    if (t instanceof String) {
                        Storage.setValue("la_" + t, dict);
                    }
                }
            }
        }
    }

    //! Haversine distance (radians in, km out).
    function haversineKm(
        lat1 as Double, lon1 as Double,
        lat2 as Double, lon2 as Double
    ) as Double {
        var dLat = lat2 - lat1;
        var dLon = lon2 - lon1;
        var sinDLat2 = Math.sin(dLat / 2.0d);
        var sinDLon2 = Math.sin(dLon / 2.0d);
        var a = sinDLat2 * sinDLat2 + Math.cos(lat1) * Math.cos(lat2) * sinDLon2 * sinDLon2;
        var c = 2.0d * Math.asin(Math.sqrt(a));
        return EARTH_RADIUS_KM * c;
    }

    //! Destination point from start (radians), bearing (radians), distance (km).
    //! Returns [latRad, lonRad].
    function destinationPoint(
        latRad as Double, lonRad as Double,
        bearingRad as Double, distKm as Double
    ) as Array<Double> {
        var dr = distKm / EARTH_RADIUS_KM;
        var lat2 = Math.asin(
            Math.sin(latRad) * Math.cos(dr) +
            Math.cos(latRad) * Math.sin(dr) * Math.cos(bearingRad)
        );
        var lon2 = lonRad + Math.atan2(
            Math.sin(bearingRad) * Math.sin(dr) * Math.cos(latRad),
            Math.cos(dr) - Math.sin(latRad) * Math.sin(lat2)
        );
        return [lat2, lon2] as Array<Double>;
    }

    //! Get wind units string for the proxy query parameter.
    function getWindUnitsString() as String {
        var val = Application.Properties.getValue("windUnits");
        if (val instanceof Number) {
            switch (val) {
                case 1: return "knots";
                case 2: return "mph";
                case 3: return "kmh";
                case 4: return "mps";
            }
        }
        return "beaufort";
    }

    //! Build the slots query parameter from slot count and intervals.
    function buildSlotsString() as String {
        if (_slotCount <= 1) {
            return "0";
        }

        var i1 = getForecastInterval(1);
        if (_slotCount == 2) {
            return "0," + i1.toString();
        }

        var i2 = getForecastInterval(2);
        if (i2 <= i1) {
            i2 = i1 + 1;
            if (i2 > 6) { i2 = 6; }
        }
        return "0," + i1.toString() + "," + i2.toString();
    }

    //! Read a forecast interval setting (1 or 2).
    function getForecastInterval(which as Number) as Number {
        var key = (which == 1) ? "forecastInterval1" : "forecastInterval2";
        var val = Application.Properties.getValue(key);
        if (val instanceof Number && val >= 1 && val <= 6) {
            return val;
        }
        return (which == 1) ? 3 : 6;
    }

}
