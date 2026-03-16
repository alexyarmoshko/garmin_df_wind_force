import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// Layout width thresholds (px) -- tune after on-device testing
const THRESHOLD_2_SLOT = 90;
const THRESHOLD_3_SLOT = 150;

// Staleness threshold in seconds (30 minutes)
const STALE_THRESHOLD_SEC = 1800;

module DisplayRenderer {

    // Translatable display strings (loaded once via init)
    var sNoGps as String = "";
    var sNoForecast as String = "";
    var sStalePrefix as String = "";
    var sSlotSeparator as String = "";

    //! Load translatable strings from resources. Call once at startup.
    function init() as Void {
        sNoGps = WatchUi.loadResource($.Rez.Strings.NoGps) as String;
        sNoForecast = WatchUi.loadResource($.Rez.Strings.NoForecast) as String;
        sStalePrefix = WatchUi.loadResource($.Rez.Strings.StalePrefix) as String;
        sSlotSeparator = WatchUi.loadResource($.Rez.Strings.SlotSeparator) as String;
    }

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
                return sNoGps;
            }
            return sNoForecast;
        }

        var result = "";

        // Prefix with stale indicator when data is old
        if (fetchTimestamp > 0) {
            var age = Time.now().value() - fetchTimestamp;
            if (age > STALE_THRESHOLD_SEC) {
                result = sStalePrefix;
            }
        }

        result += renderWindSlot(forecasts[0]);
        for (var i = 1; i < forecasts.size(); i++) {
            result += sSlotSeparator;
            result += renderWindSlot(forecasts[i]);
        }

        return result;
    }

    //! Render a single time slot: "W/GD" (e.g. "9/23S")
    function renderWindSlot(data as WindData) as String {
        return data.windSpeed.toString() + "/" + data.gustSpeed.toString() + data.windDir;
    }

}
