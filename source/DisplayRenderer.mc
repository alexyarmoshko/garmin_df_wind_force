import Toybox.Lang;
import Toybox.Math;

// Wind unit constants (match settings values in properties.xml)
enum /* WindUnits */ {
    UNIT_BEAUFORT = 0,
    UNIT_KNOTS = 1,
    UNIT_MPH = 2,
    UNIT_KMH = 3,
    UNIT_MPS = 4
}

// Layout width thresholds (px) — tune after on-device testing
const THRESHOLD_2_SLOT = 90;
const THRESHOLD_3_SLOT = 150;

// 8 cardinal/intercardinal direction labels, indexed by 45-degree increments
// Index 0 = N (337.5–22.5 deg), 1 = NE (22.5–67.5), ... 7 = NW (292.5–337.5)
const DIRECTION_LABELS as Array<String> = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];

module DisplayRenderer {

    // ── Public API ───────────────────────────────────────────────────

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
    //! @param forecasts Array of WindData (at least 1 entry)
    //! @param slots Number of time slots to render (1, 2 or 3)
    //! @param units WindUnits enum value
    function formatLayout(
        forecasts as Array<WindData>,
        slots as Number,
        units as Number
    ) as String {
        if (forecasts.size() == 0) {
            return "?";
        }

        var result = renderWindSlot(forecasts[0], units);

        if (slots >= 2 && forecasts.size() >= 2) {
            result += veerBackSymbol(forecasts[0].windDeg, forecasts[1].windDeg);
            result += renderWindSlot(forecasts[1], units);
        }

        if (slots >= 3 && forecasts.size() >= 3) {
            result += veerBackSymbol(forecasts[1].windDeg, forecasts[2].windDeg);
            result += renderWindSlot(forecasts[2], units);
        }

        return result;
    }

    // ── Helpers ──────────────────────────────────────────────────────

    //! Render a single time slot: "S(G)D"
    function renderWindSlot(data as WindData, units as Number) as String {
        var speed = convertSpeed(data.windMps, data.windBeaufort, data.gustMps, units);
        var dir = directionLabel(data.windDeg);
        return speed[0] + "(" + speed[1] + ")" + dir;
    }

    //! Convert wind and gust speed to the target unit, returning [speedStr, gustStr].
    function convertSpeed(
        mps as Float,
        beaufort as Number,
        gustMps as Float,
        units as Number
    ) as Array<String> {
        switch (units) {
            case UNIT_BEAUFORT:
                // Beaufort for speed; gust has no Beaufort value, show in same scale
                // Approximate gust Beaufort from m/s using the Beaufort breakpoints
                return [beaufort.toString(), mpsToBeaufort(gustMps).toString()];
            case UNIT_KNOTS:
                return [Math.round(mps * 1.94384).format("%d"), Math.round(gustMps * 1.94384).format("%d")];
            case UNIT_MPH:
                return [Math.round(mps * 2.23694).format("%d"), Math.round(gustMps * 2.23694).format("%d")];
            case UNIT_KMH:
                return [Math.round(mps * 3.6).format("%d"), Math.round(gustMps * 3.6).format("%d")];
            case UNIT_MPS:
                return [Math.round(mps).format("%d"), Math.round(gustMps).format("%d")];
            default:
                return [beaufort.toString(), mpsToBeaufort(gustMps).toString()];
        }
    }

    //! Map a degree heading to one of 8 cardinal/intercardinal labels.
    function directionLabel(deg as Number) as String {
        // Normalize to 0..359, divide into 8 sectors of 45 degrees each
        var idx = (((deg + 22) % 360) / 45).toNumber();
        if (idx < 0) { idx += 8; }
        if (idx > 7) { idx = 0; }
        return DIRECTION_LABELS[idx];
    }

    //! Return a veering/backing symbol between two direction values.
    //! Veering (clockwise) = ">", Backing (anticlockwise) = "<", No change = ">".
    function veerBackSymbol(deg1 as Number, deg2 as Number) as String {
        var diff = deg2 - deg1;
        // Normalize to -180..180
        while (diff > 180) { diff -= 360; }
        while (diff < -180) { diff += 360; }

        if (diff > 0) {
            return ">";  // veering (clockwise)
        } else if (diff < 0) {
            return "<";  // backing (anticlockwise)
        }
        return ">";  // no change, use separator
    }

    //! Approximate Beaufort scale from m/s using standard breakpoints.
    function mpsToBeaufort(mps as Float) as Number {
        if (mps < 0.3) { return 0; }
        if (mps < 1.6) { return 1; }
        if (mps < 3.4) { return 2; }
        if (mps < 5.5) { return 3; }
        if (mps < 8.0) { return 4; }
        if (mps < 10.8) { return 5; }
        if (mps < 13.9) { return 6; }
        if (mps < 17.2) { return 7; }
        if (mps < 20.8) { return 8; }
        if (mps < 24.5) { return 9; }
        if (mps < 28.5) { return 10; }
        if (mps < 32.7) { return 11; }
        return 12;
    }

}
