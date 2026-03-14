import Toybox.Lang;
import Toybox.Time;

// Layout width thresholds (px) -- tune after on-device testing
const THRESHOLD_2_SLOT = 90;
const THRESHOLD_3_SLOT = 150;

// Staleness threshold in seconds (30 minutes)
const STALE_THRESHOLD_SEC = 1800;

module DisplayRenderer {

    //! Determine how many time slots fit in the given width.
    function slotCount(width as Number) as Number {
        if (width >= THRESHOLD_3_SLOT) {
            return 3;
        }
        if (width >= THRESHOLD_2_SLOT) {
            return 2;
        }
        return 1;
    }

    //! Build the full display string for the given forecasts.
    //! @param forecasts Array of WindData (may be empty)
    //! @param fetchTimestamp Unix epoch seconds of last successful fetch (0 if never)
    //! @param hasPosition Whether GPS position is available
    function formatLayout(
        forecasts as Array<WindData>,
        fetchTimestamp as Number,
        hasPosition as Boolean
    ) as String {
        if (forecasts.size() == 0) {
            if (!hasPosition) {
                return "NO GPS";
            }
            return "---";
        }

        var result = renderWindSlot(forecasts[0]);

        for (var i = 1; i < forecasts.size(); i++) {
            var v = forecasts[i].veer;
            result += (v != null) ? v : ">";
            result += renderWindSlot(forecasts[i]);
        }

        // Staleness indicator
        if (fetchTimestamp > 0) {
            var age = Time.now().value() - fetchTimestamp;
            if (age > STALE_THRESHOLD_SEC) {
                var ageMin = age / 60;
                result += "*" + ageMin.toString() + "m";
            }
        }

        return result;
    }

    //! Render a single time slot: "S(G)D"
    function renderWindSlot(data as WindData) as String {
        return data.windSpeed.toString() + "(" + data.gustSpeed.toString() + ")" + data.windDir;
    }

}
