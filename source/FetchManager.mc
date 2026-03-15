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

    function initialize() {
    }

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
            }
            return;
        }

        var coords = (loc as Position.Location).toRadians();
        var latRad = coords[0] as Double;
        var lonRad = coords[1] as Double;

        currentLatDeg = latRad * 180.0d / Math.PI;
        currentLonDeg = lonRad * 180.0d / Math.PI;
        hasPosition = true;

        // Persist position for the background service to read
        Storage.setValue("bg_lat", currentLatDeg);
        Storage.setValue("bg_lon", currentLonDeg);
    }

}
