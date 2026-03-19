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
    var sNoForecastSlot as String = "";
    var sStalePrefix as String = "";
    var sSlotSeparator as String = "";

    // Display mode: when true, cardinal labels are replaced by arrow glyphs
    var useArrows as Boolean = false;

    // Internal mode for custom BMFonts that encode arrows/separators onto
    // ASCII placeholder glyph ids instead of their Unicode code points.
    var useCustomGlyphPlaceholders as Boolean = false;

    //! Load translatable strings from resources. Call once at startup.
    function init() as Void {
        sNoGps = WatchUi.loadResource($.Rez.Strings.NoGps) as String;
        sNoForecastSlot = WatchUi.loadResource($.Rez.Strings.NoForecastSlot) as String;
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
    //! @param isStale Whether the forecast data is older than STALE_THRESHOLD_SEC
    //! @param hasPosition Whether GPS position is available
    //! @param slots Number of time slots to display
    function formatLayout(
        forecasts as Array<WindData>,
        isStale as Boolean,
        hasPosition as Boolean,
        slots as Number
    ) as String {
        if (forecasts.size() == 0) {
            if (!hasPosition) {
                return sNoGps;
            }
            var noData = sNoForecastSlot;
            for (var i = 1; i < slots; i++) {
                noData += slotSeparator() + sNoForecastSlot;
            }
            return noData;
        }

        var result = "";

        if (isStale) {
            result = sStalePrefix;
        }

        var n = (forecasts.size() < slots) ? forecasts.size() : slots;
        result += renderWindSlot(forecasts[0]);
        for (var i = 1; i < n; i++) {
            result += slotSeparator();
            result += renderWindSlot(forecasts[i]);
        }

        return result;
    }

    //! Render a single time slot: "W/GD" (e.g. "9/23S") or "W/G↑" in arrows mode.
    function renderWindSlot(data as WindData) as String {
        var dir = useArrows ? dirToArrow(data.windDir) : data.windDir;
        return data.windSpeed.toString() + "/" + data.gustSpeed.toString() + dir;
    }

    //! Choose the separator matching the active font family.
    function slotSeparator() as String {
        return useCustomGlyphPlaceholders ? "|" : sSlotSeparator;
    }

    //! Map a cardinal "wind from" label to a BMFont placeholder glyph id.
    //! The custom BMFont maps arrow glyphs to these ASCII code points.
    //! Only called when useArrows && hasPosition, so the custom font is
    //! always active — no Unicode fallback needed.
    //! Returns the original label if no mapping exists.
    function dirToArrow(dir as String) as String {
        // Wind blows FROM the named direction; arrow shows where it goes TO.
        if (dir.equals("N"))  { return "d"; } // ↓
        if (dir.equals("NE")) { return "h"; } // ↙
        if (dir.equals("E"))  { return "a"; } // ←
        if (dir.equals("SE")) { return "e"; } // ↖
        if (dir.equals("S"))  { return "b"; } // ↑
        if (dir.equals("SW")) { return "f"; } // ↗
        if (dir.equals("W"))  { return "c"; } // →
        if (dir.equals("NW")) { return "g"; } // ↘
        return dir;
    }

}
