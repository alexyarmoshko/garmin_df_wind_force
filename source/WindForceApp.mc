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

    function getInitialView() as [Views] or [Views, InputDelegates] {
        // Register background temporal event (5-min interval).
        // Using Duration means it fires immediately if >5 min since last run.
        Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        return [new WindForceView()];
    }

    //! Return the service delegate for background web requests.
    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new WindForceServiceDelegate()];
    }

    //! Called when the background service returns data.
    function onBackgroundData(data as Application.PersistableType) as Void {
        if (data instanceof Dictionary) {
            var dict = data as Dictionary;
            var kind = dict["kind"];

            if ("forecast".equals(kind)) {
                var payload = dict["payload"];
                if (payload instanceof Dictionary) {
                    var rLat = dict["rLat"];
                    var rLon = dict["rLon"];
                    if (rLat instanceof String && rLon instanceof String) {
                        StorageManager.storeForecast(rLat, rLon, payload as Dictionary);
                        Storage.setValue("last_fetch_ts", Time.now().value());

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
