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
    //! Assumes _validateIntervals() has already ensured i2 > i1.
    function getSlotsString() as String {
        var i1 = getInterval(1);
        var i2 = getInterval(2);
        if (i2 > 6) {
            return "0," + i1.toString();
        }
        return "0," + i1.toString() + "," + i2.toString();
    }

    //! Read a forecast interval setting.
    function getInterval(which as Number) as Number {
        var key = (which == 1) ? "forecastInterval1" : "forecastInterval2";
        var val = Application.Properties.getValue(key);
        if (val instanceof Number && val >= 1 && val <= 6) {
            return val;
        }
        return (which == 1) ? 3 : 6;
    }

}
