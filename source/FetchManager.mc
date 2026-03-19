import Toybox.Activity;
import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;

//! Tracks GPS position and persists it to Storage for the background service.
class FetchManager {

    // Current GPS position in degrees (updated each compute cycle for view lookup)
    var currentLatDeg as Double = 0.0d;
    var currentLonDeg as Double = 0.0d;
    var hasPosition as Boolean = false;

    // Set to true on the no-GPS → GPS transition so the view can
    // schedule an immediate background fetch.
    var gpsJustAcquired as Boolean = false;

    // Last position written to Storage. Used to throttle writes:
    // background service reads every 5 min, so writing every second
    // is wasteful. Only persist when moved > 0.001 deg (~100 m).
    private var _lastStoredLat as Double = 0.0d;
    private var _lastStoredLon as Double = 0.0d;

    //! Called from compute(). Saves current GPS position to Storage
    //! for the background service to read when it fires.
    //! Clears position when GPS fix is lost so the display reverts to
    //! "NO GPS" and the background service stops using stale coordinates.
    function updatePosition(info as Activity.Info) as Void {
        var loc = info.currentLocation;
        if (loc == null) {
            if (hasPosition) {
                hasPosition = false;
                Storage.deleteValue("bg_lat");
                Storage.deleteValue("bg_lon");
                // Reset so next GPS fix always persists immediately
                _lastStoredLat = 0.0d;
                _lastStoredLon = 0.0d;
            }
            return;
        }

        var coords = (loc as Position.Location).toRadians();
        var latRad = coords[0] as Double;
        var lonRad = coords[1] as Double;

        currentLatDeg = latRad * 180.0d / Math.PI;
        currentLonDeg = lonRad * 180.0d / Math.PI;

        // Detect no-GPS → GPS transition
        if (!hasPosition) {
            gpsJustAcquired = true;
        }
        hasPosition = true;

        // Persist position for the background service, but throttle writes:
        // service reads every 5 min, so only write when moved > ~100 m.
        var dLat = currentLatDeg - _lastStoredLat;
        var dLon = currentLonDeg - _lastStoredLon;
        if (dLat > 0.001 || dLat < -0.001 ||
            dLon > 0.001 || dLon < -0.001) {
            Storage.setValue("bg_lat", currentLatDeg);
            Storage.setValue("bg_lon", currentLonDeg);
            _lastStoredLat = currentLatDeg;
            _lastStoredLon = currentLonDeg;
        }
    }

}
