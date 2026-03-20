import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:background)
module DiagnosticsLog {

    // Toggle field-test device logging here.
    const ENABLE_DEVICE_LOGS = true;

    //! Write a compact diagnostic line to the device log when enabled.
    function log(message as String) as Void {
        if (!ENABLE_DEVICE_LOGS) {
            return;
        }

        System.println(timestamp() + " " + message);
    }

    //! Log a short event plus the HTTP/background response code.
    function logResponseCode(message as String, responseCode as Number) as Void {
        if (!ENABLE_DEVICE_LOGS) {
            return;
        }

        System.println(timestamp() + " " + message + " rc=" + responseCode.toString());
    }

    function timestamp() as String {
        var nowInfo = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return Lang.format(
            "$1$-$2$-$3$ $4$:$5$:$6$",
            [
                nowInfo.year.toString(),
                nowInfo.month.toString(),
                nowInfo.day.toString(),
                nowInfo.hour.toString(),
                nowInfo.min.toString(),
                nowInfo.sec.toString()
            ]
        );
    }

}
