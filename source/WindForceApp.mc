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
    //! Clears cached forecasts to prevent displaying data fetched under
    //! old unit/interval settings. Fresh data arrives on the next background event.
    // Foreground-only: references StorageManager and WatchUi (not in background scope)
    (:typecheck(false))
    function onSettingsChanged() as Void {
        // Bump settings version so in-flight background responses fetched
        // under old settings are rejected by onBackgroundData().
        var ver = Storage.getValue("settings_ver");
        var newVer = (ver instanceof Number) ? (ver as Number) + 1 : 1;
        Storage.setValue("settings_ver", newVer);

        StorageManager.clearAllForecasts();
        WatchUi.requestUpdate();
    }

    //! Return the service delegate for background web requests.
    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new WindForceServiceDelegate()];
    }

    //! Called when the background service returns data.
    // Foreground-only: references StorageManager and WatchUi (not in background scope)
    (:typecheck(false))
    function onBackgroundData(data as Application.PersistableType) as Void {
        if (data instanceof Dictionary) {
            var dict = data as Dictionary;
            var kind = dict["kind"];

            if ("forecast".equals(kind)) {
                // Reject responses fetched under old settings (in-flight
                // during a settings change). Version 0 = no change yet.
                var responseSv = dict["sv"];
                var curSv = Storage.getValue("settings_ver");
                var rVer = (responseSv instanceof Number) ? responseSv as Number : 0;
                var cVer = (curSv instanceof Number) ? curSv as Number : 0;
                if (rVer != cVer) {
                    // Stale settings — discard payload, still refresh display
                    WatchUi.requestUpdate();
                    return;
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
