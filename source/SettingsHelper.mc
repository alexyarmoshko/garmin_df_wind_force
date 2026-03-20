import Toybox.Application;
import Toybox.Lang;

//! Shared settings helpers used by both foreground app and background delegate.
(:background)
module SettingsHelper {

    //! Read wind units setting and return as API string.
    function getUnitsString() as String {
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

    //! Build slots query parameter from interval settings.
    //! Both intervals are increments (+1h to +6h). Interval 1 is
    //! the offset from now (0h); interval 2 is the offset from
    //! interval 1. The proxy receives absolute hours: "0,i1,i1+i2".
    function getSlotsString() as String {
        var i1 = getInterval(1);
        var i2 = getInterval(2);
        var slot3 = i1 + i2;
        return "0," + i1.toString() + "," + slot3.toString();
    }

    //! Read a forecast interval setting (increment, +1h to +6h).
    function getInterval(which as Number) as Number {
        var key = (which == 1) ? "forecastInterval1" : "forecastInterval2";
        var val = Application.Properties.getValue(key);
        if (val instanceof Number && val >= 1 && val <= 6) {
            return val;
        }
        return 3;
    }

}
