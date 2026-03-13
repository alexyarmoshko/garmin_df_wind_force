import Toybox.Communications;
import Toybox.Lang;

// Proxy base URL
const PROXY_BASE_URL = "https://wind-force-proxy.alex-cc4.workers.dev";

module ForecastService {

    //! Fetch forecast data from the proxy.
    //! @param lat Latitude in degrees (proxy expects degrees)
    //! @param lon Longitude in degrees (proxy expects degrees)
    //! @param units Wind unit string: "beaufort", "knots", "mph", "kmh", "mps"
    //! @param slots Comma-separated hour offsets, e.g. "0,3,6"
    //! @param callback Method(responseCode, data) to receive the result
    function fetchForecast(
        lat as Double,
        lon as Double,
        units as String,
        slots as String,
        callback as Method(responseCode as Number, data as Dictionary or String or Null) as Void
    ) as Void {
        var url = PROXY_BASE_URL + "/forecast";
        var params = {
            "lat" => lat.format("%.3f"),
            "lon" => lon.format("%.3f"),
            "units" => units,
            "slots" => slots
        };
        var options = {
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(url, params, options, callback);
    }

    //! Fetch the latest model run timestamp from the proxy.
    //! @param callback Method(responseCode, data) to receive the result
    function fetchModelStatus(
        callback as Method(responseCode as Number, data as Dictionary or String or Null) as Void
    ) as Void {
        var url = PROXY_BASE_URL + "/model-status";
        var options = {
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(url, null, options, callback);
    }

}
