import Toybox.Lang;

// Layout width thresholds (px) -- tune after on-device testing
const THRESHOLD_2_SLOT = 90;
const THRESHOLD_3_SLOT = 150;

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
    //! The forecasts array already contains exactly the entries requested
    //! via the proxy's slots parameter, with pre-converted values and
    //! veer/back symbols.
    //! @param forecasts Array of WindData
    //! @param fetchTimestamp Unix epoch seconds of last successful fetch
    function formatLayout(
        forecasts as Array<WindData>,
        fetchTimestamp as Number
    ) as String {
        if (forecasts.size() == 0) {
            return "?(?)";
        }

        var result = renderWindSlot(forecasts[0]);

        for (var i = 1; i < forecasts.size(); i++) {
            var v = forecasts[i].veer;
            result += (v != null) ? v : ">";
            result += renderWindSlot(forecasts[i]);
        }

        return result;
    }

    //! Render a single time slot: "S(G)D"
    function renderWindSlot(data as WindData) as String {
        return data.windSpeed + "(" + data.gustSpeed + ")" + data.windDir;
    }

}
