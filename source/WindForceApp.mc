import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

(:background)
class WindForceApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
        Background.deleteTemporalEvent();
    }

    // Foreground-only: references WindForceView (not in background scope)
    (:typecheck(false))
    function getInitialView() as [Views] or [Views, InputDelegates] {
        // Register background temporal event (5-min interval).
        // Using Duration means it fires immediately if >5 min since last run.
        Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        return [new WindForceView()];
    }

    //! Called when settings change via Garmin Connect Mobile / Express.
    //! Validates interval pair, clears cached forecasts, and refreshes display.
    // Foreground-only: references StorageManager and WatchUi (not in background scope)
    (:typecheck(false))
    function onSettingsChanged() as Void {
        _validateIntervals();
        StorageManager.clearAllForecasts();
        WatchUi.requestUpdate();
    }

    //! Ensure forecastInterval2 > forecastInterval1.
    //! Writes corrected values back to Application.Properties so the
    //! Garmin Connect settings UI reflects the effective configuration.
    private function _validateIntervals() as Void {
        var i1v = Application.Properties.getValue("forecastInterval1");
        var i2v = Application.Properties.getValue("forecastInterval2");
        if (!(i1v instanceof Number) || !(i2v instanceof Number)) {
            return;
        }
        var i1 = i1v as Number;
        var i2 = i2v as Number;
        if (i2 > i1) {
            return; // Already valid
        }
        // Correct: bump i2 to i1 + 1 when possible
        if (i1 < 6) {
            Application.Properties.setValue("forecastInterval2", i1 + 1);
        } else {
            // i1 = 6 leaves no valid i2; reduce i1 to make room
            Application.Properties.setValue("forecastInterval1", 5);
            Application.Properties.setValue("forecastInterval2", 6);
        }
    }

    //! Return the service delegate for background web requests.
    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new WindForceServiceDelegate()];
    }

    //! Compute the current wind-units string from Application.Properties.
    //! Mirrors WindForceServiceDelegate.getUnitsString() so the foreground
    //! can validate that a background response used the current settings.
    private function _currentUnitsString() as String {
        var val = Application.Properties.getValue("windUnits");
        if (val instanceof Number) {
            switch (val as Number) {
                case 1: return "knots";
                case 2: return "mph";
                case 3: return "kmh";
                case 4: return "mps";
            }
        }
        return "beaufort";
    }

    //! Compute the current slots string from Application.Properties.
    //! Mirrors WindForceServiceDelegate.getSlotsString().
    private function _currentSlotsString() as String {
        var i1v = Application.Properties.getValue("forecastInterval1");
        var i2v = Application.Properties.getValue("forecastInterval2");
        var i1 = (i1v instanceof Number && (i1v as Number) >= 1 && (i1v as Number) <= 6) ? i1v as Number : 3;
        var i2 = (i2v instanceof Number && (i2v as Number) >= 1 && (i2v as Number) <= 6) ? i2v as Number : 6;
        if (i2 <= i1) { i2 = i1 + 1; }
        if (i2 > 6) {
            return "0," + i1.toString();
        }
        return "0," + i1.toString() + "," + i2.toString();
    }

    //! Called when the background service returns data.
    // Foreground-only: references StorageManager and WatchUi (not in background scope)
    (:typecheck(false))
    function onBackgroundData(data as Application.PersistableType) as Void {
        if (data instanceof Dictionary) {
            var dict = data as Dictionary;
            var kind = dict["kind"];

            if ("forecast".equals(kind)) {
                // Reject responses fetched under stale settings by comparing
                // the actual units/slots used in the request against current
                // Application.Properties values. This eliminates the race
                // where Storage and Properties sync at different times.
                var rUnits = dict["reqUnits"];
                var rSlots = dict["reqSlots"];
                if (rUnits instanceof String && rSlots instanceof String) {
                    var curUnits = _currentUnitsString();
                    var curSlots = _currentSlotsString();
                    if (!curUnits.equals(rUnits) || !curSlots.equals(rSlots)) {
                        WatchUi.requestUpdate();
                        return;
                    }
                }

                var payload = dict["payload"];
                if (payload instanceof Dictionary) {
                    var rLat = dict["rLat"];
                    var rLon = dict["rLon"];
                    if (rLat instanceof String && rLon instanceof String) {
                        // Stamp each forecast with its own fetch time so the
                        // staleness indicator tracks the displayed data, not the
                        // most recent fetch for any location.
                        var payloadDict = payload as Dictionary;
                        payloadDict.put("fetch_ts", Time.now().value());
                        StorageManager.storeForecast(rLat, rLon, payloadDict);

                        var mr = (payload as Dictionary)["model_run"];
                        if (mr instanceof String) {
                            Storage.setValue("last_model_run", mr);
                        }
                    }
                }
            } else if ("model_status".equals(kind)) {
                var mr = dict["model_run"];
                if (mr instanceof String) {
                    var prev = Storage.getValue("last_model_run");
                    if (!(prev instanceof String) || !(prev as String).equals(mr)) {
                        Storage.setValue("last_model_run", mr);
                        Storage.setValue("last_fetch_ts", 0);
                    }
                }
            }
        }
        WatchUi.requestUpdate();
    }

}
