import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;

(:background)
class WindForceServiceDelegate extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    //! Called when the background temporal event fires.
    function onTemporalEvent() as Void {
        // Read current position saved by compute()
        var lat = Storage.getValue("bg_lat");
        var lon = Storage.getValue("bg_lon");

        if (lat == null || lon == null) {
            // No position available yet — exit immediately
            DiagnosticsLog.log("fetch_skip");
            Background.exit({"kind" => "error", "rc" => -1});
            return;
        }

        var latDeg = (lat instanceof Double) ? lat as Double :
                     (lat instanceof Float) ? (lat as Float).toDouble() : 0.0d;
        var lonDeg = (lon instanceof Double) ? lon as Double :
                     (lon instanceof Float) ? (lon as Float).toDouble() : 0.0d;

        var units = SettingsHelper.getUnitsString();
        var slots = SettingsHelper.getSlotsString();

        var rLat = GeoUtils.roundCoord(latDeg);
        var rLon = GeoUtils.roundCoord(lonDeg);
        DiagnosticsLog.log("fetch_start");

        var url = "https://api-wind-force.kayakshaver.com/v1/forecast";
        var params = {
            "lat" => latDeg.format("%.3f"),
            "lon" => lonDeg.format("%.3f"),
            "units" => units,
            "slots" => slots
        };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        // Store request metadata so onForecastReceived can include it
        // in Background.exit() for foreground settings validation.
        Storage.setValue("bg_rLat", rLat);
        Storage.setValue("bg_rLon", rLon);
        Storage.setValue("bg_reqUnits", units);
        Storage.setValue("bg_reqSlots", slots);

        Communications.makeWebRequest(url, params, options, method(:onForecastReceived));
    }

    //! Callback for the forecast web request.
    // Framework types Dictionary and Background.exit(PersistableType) are
    // incompatible at -l 3; safe at runtime.
    (:typecheck(false))
    function onForecastReceived(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data instanceof Dictionary) {
            var rLat = Storage.getValue("bg_rLat");
            var rLon = Storage.getValue("bg_rLon");
            var rUnits = Storage.getValue("bg_reqUnits");
            var rSlots = Storage.getValue("bg_reqSlots");
            DiagnosticsLog.logResponseCode("fetch_ok", responseCode);
            Background.exit({
                "kind" => "forecast",
                "payload" => data,
                "rLat" => (rLat instanceof String) ? rLat : "0.000",
                "rLon" => (rLon instanceof String) ? rLon : "0.000",
                "reqUnits" => (rUnits instanceof String) ? rUnits : "",
                "reqSlots" => (rSlots instanceof String) ? rSlots : ""
            });
        } else {
            DiagnosticsLog.logResponseCode("fetch_fail", responseCode);
            Background.exit({
                "kind" => "error",
                "rc" => responseCode
            });
        }
    }

    //! Called when an activity is completed (saved or discarded).
    //! Signals the foreground to clear cached forecasts.
    (:typecheck(false))
    function onActivityCompleted(activity) as Void {
        DiagnosticsLog.log("activity_completed");
        Background.exit({"kind" => "session_end"});
    }

}
