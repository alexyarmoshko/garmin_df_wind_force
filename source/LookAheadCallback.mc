import Toybox.Lang;

//! Captures look-ahead coordinates immutably at dispatch time so the
//! callback stores data under the correct grid point regardless of
//! when the async response arrives or whether a new fetch cycle has
//! started in the meantime.
class LookAheadCallback {

    private var _latDeg as Double;
    private var _lonDeg as Double;

    function initialize(latDeg as Double, lonDeg as Double) {
        _latDeg = latDeg;
        _lonDeg = lonDeg;
    }

    //! makeWebRequest callback — stores the response via StorageManager.
    function onReceived(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data instanceof Dictionary) {
            var rLat = StorageManager.roundCoord(_latDeg);
            var rLon = StorageManager.roundCoord(_lonDeg);
            StorageManager.storeForecast(rLat, rLon, data as Dictionary);
        }
    }

}
