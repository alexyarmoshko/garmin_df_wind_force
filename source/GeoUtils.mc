import Toybox.Lang;
import Toybox.Math;

module GeoUtils {

    //! Round a coordinate to the nearest 0.025-degree grid cell.
    //! Uses integer grid steps to avoid midpoint drift from 0.025.
    function roundCoord(value as Double) as String {
        var rounded = (Math.round(value * 40.0d).toDouble()) / 40.0d;
        return rounded.format("%.3f");
    }

}
