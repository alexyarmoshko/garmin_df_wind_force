import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;

//
// Unit tests for pure functions in the Wind Force data field.
// Run with: monkeyc --unit-test ... then connectiq + test <device>
// The (:test) annotation excludes these from release builds automatically.
//

// ── GeoUtils.roundCoord ─────────────────────────────────────────

(:test)
function testRoundCoordPositive(logger as Test.Logger) as Boolean {
    // 53.347 rounds to nearest 0.025 → 53.350
    var result = GeoUtils.roundCoord(53.347d);
    logger.debug("roundCoord(53.347) = " + result);
    return result.equals("53.350");
}

(:test)
function testRoundCoordNegative(logger as Test.Logger) as Boolean {
    // -6.260 rounds to nearest 0.025 → -6.250  (round toward zero)
    // Actually: -6.260 / 0.025 = -250.4, round = -250, * 0.025 = -6.250
    var result = GeoUtils.roundCoord(-6.260d);
    logger.debug("roundCoord(-6.260) = " + result);
    return result.equals("-6.250");
}

(:test)
function testRoundCoordExactGrid(logger as Test.Logger) as Boolean {
    // Value already on grid should stay unchanged
    var result = GeoUtils.roundCoord(53.350d);
    logger.debug("roundCoord(53.350) = " + result);
    return result.equals("53.350");
}

(:test)
function testRoundCoordZero(logger as Test.Logger) as Boolean {
    var result = GeoUtils.roundCoord(0.0d);
    logger.debug("roundCoord(0.0) = " + result);
    return result.equals("0.000");
}

(:test)
function testRoundCoordMidpoint(logger as Test.Logger) as Boolean {
    // 53.3375 is exactly between 53.325 and 53.350
    // Math.round rounds to nearest; 53.3375/0.025 = 2133.5 → 2134 → 53.350
    var result = GeoUtils.roundCoord(53.3375d);
    logger.debug("roundCoord(53.3375) = " + result);
    return result.equals("53.350");
}

(:test)
function testRoundCoordSmallNegative(logger as Test.Logger) as Boolean {
    // -0.012 / 0.025 = -0.48, round = 0, * 0.025 = 0.000
    var result = GeoUtils.roundCoord(-0.012d);
    logger.debug("roundCoord(-0.012) = " + result);
    return result.equals("0.000");
}

// ── StorageManager.splitFcKey ─────────────────────────────────────────

(:test)
function testSplitFcKeyValid(logger as Test.Logger) as Boolean {
    var parts = StorageManager.splitFcKey("fc_53.350_-6.250");
    if (parts == null) {
        logger.debug("splitFcKey returned null for valid key");
        return false;
    }
    logger.debug("lat=" + parts[0] + " lon=" + parts[1]);
    return (parts[0] as String).equals("53.350") &&
           (parts[1] as String).equals("-6.250");
}

(:test)
function testSplitFcKeyNegativeLat(logger as Test.Logger) as Boolean {
    // Negative latitude: separator is after first digit group
    var parts = StorageManager.splitFcKey("fc_-33.900_151.200");
    if (parts == null) {
        logger.debug("splitFcKey returned null for negative lat key");
        return false;
    }
    logger.debug("lat=" + parts[0] + " lon=" + parts[1]);
    return (parts[0] as String).equals("-33.900") &&
           (parts[1] as String).equals("151.200");
}

(:test)
function testSplitFcKeyBothNegative(logger as Test.Logger) as Boolean {
    var parts = StorageManager.splitFcKey("fc_-33.900_-151.200");
    if (parts == null) {
        logger.debug("splitFcKey returned null for both-negative key");
        return false;
    }
    logger.debug("lat=" + parts[0] + " lon=" + parts[1]);
    return (parts[0] as String).equals("-33.900") &&
           (parts[1] as String).equals("-151.200");
}

(:test)
function testSplitFcKeyTooShort(logger as Test.Logger) as Boolean {
    var result = StorageManager.splitFcKey("fc");
    logger.debug("splitFcKey('fc') = " + result);
    return (result == null);
}

(:test)
function testSplitFcKeyNoSeparator(logger as Test.Logger) as Boolean {
    var result = StorageManager.splitFcKey("fc_53.350");
    logger.debug("splitFcKey('fc_53.350') = " + result);
    return (result == null);
}

// ── StorageManager.approxDistKm ───────────────────────────────────────

(:test)
function testApproxDistSamePoint(logger as Test.Logger) as Boolean {
    var dist = StorageManager.approxDistKm(53.35d, -6.25d, 53.35d, -6.25d);
    logger.debug("dist same point = " + dist);
    return (dist < 0.001);
}

(:test)
function testApproxDistKnown(logger as Test.Logger) as Boolean {
    // Dublin (53.35, -6.26) to a point ~2.8 km north (53.375, -6.26)
    // 0.025 deg lat ≈ 2.78 km
    var dist = StorageManager.approxDistKm(53.350d, -6.260d, 53.375d, -6.260d);
    logger.debug("dist 0.025 deg lat = " + dist);
    return (dist > 2.5 && dist < 3.1);
}

(:test)
function testApproxDistWithinGrid(logger as Test.Logger) as Boolean {
    // Two points within the same 0.025-degree grid cell should be < 2.5 km
    var dist = StorageManager.approxDistKm(53.350d, -6.250d, 53.360d, -6.255d);
    logger.debug("dist within grid = " + dist);
    return (dist < 2.5);
}

(:test)
function testApproxDistSymmetric(logger as Test.Logger) as Boolean {
    var d1 = StorageManager.approxDistKm(53.35d, -6.25d, 53.40d, -6.30d);
    var d2 = StorageManager.approxDistKm(53.40d, -6.30d, 53.35d, -6.25d);
    logger.debug("d1=" + d1 + " d2=" + d2);
    var diff = d1 - d2;
    if (diff < 0) { diff = -diff; }
    return (diff < 0.01);
}

// ── DisplayRenderer.slotCount ─────────────────────────────────────────

(:test)
function testSlotCount1(logger as Test.Logger) as Boolean {
    // Width below THRESHOLD_2_SLOT (90) → 1 slot
    var count = DisplayRenderer.slotCount(80);
    logger.debug("slotCount(80) = " + count);
    return (count == 1);
}

(:test)
function testSlotCount2(logger as Test.Logger) as Boolean {
    // Width at THRESHOLD_2_SLOT (90) → 2 slots
    var count = DisplayRenderer.slotCount(90);
    logger.debug("slotCount(90) = " + count);
    return (count == 2);
}

(:test)
function testSlotCount2Mid(logger as Test.Logger) as Boolean {
    // Width between thresholds → 2 slots
    var count = DisplayRenderer.slotCount(120);
    logger.debug("slotCount(120) = " + count);
    return (count == 2);
}

(:test)
function testSlotCount3(logger as Test.Logger) as Boolean {
    // Width at THRESHOLD_3_SLOT (150) → 3 slots
    var count = DisplayRenderer.slotCount(150);
    logger.debug("slotCount(150) = " + count);
    return (count == 3);
}

(:test)
function testSlotCount3Large(logger as Test.Logger) as Boolean {
    // Instinct 2X full width 176px → 3 slots
    var count = DisplayRenderer.slotCount(176);
    logger.debug("slotCount(176) = " + count);
    return (count == 3);
}

(:test)
function testSlotCountMinimum(logger as Test.Logger) as Boolean {
    // Very narrow → still 1 slot minimum
    var count = DisplayRenderer.slotCount(10);
    logger.debug("slotCount(10) = " + count);
    return (count == 1);
}

// ── DisplayRenderer.renderWindSlot ────────────────────────────────────

(:test)
function testRenderWindSlot(logger as Test.Logger) as Boolean {
    var data = new WindData("2025-01-01T12:00:00Z", 4, 7, "SW");
    var result = DisplayRenderer.renderWindSlot(data);
    logger.debug("renderWindSlot = '" + result + "'");
    return result.equals("4/7SW");
}

(:test)
function testRenderWindSlotZero(logger as Test.Logger) as Boolean {
    var data = new WindData("2025-01-01T12:00:00Z", 0, 0, "N");
    var result = DisplayRenderer.renderWindSlot(data);
    logger.debug("renderWindSlot zero = '" + result + "'");
    return result.equals("0/0N");
}

(:test)
function testRenderWindSlotLargeValues(logger as Test.Logger) as Boolean {
    var data = new WindData("2025-01-01T12:00:00Z", 12, 25, "NNE");
    var result = DisplayRenderer.renderWindSlot(data);
    logger.debug("renderWindSlot large = '" + result + "'");
    return result.equals("12/25NNE");
}

// ── DisplayRenderer.dirToArrow ────────────────────────────────────────

(:test)
function testDirToArrowCardinals(logger as Test.Logger) as Boolean {
    // All 4 cardinal directions: N→↓, E→←, S→↑, W→→
    var ok = true;
    ok = ok && DisplayRenderer.dirToArrow("N").equals(0x2193.toChar().toString());
    ok = ok && DisplayRenderer.dirToArrow("E").equals(0x2190.toChar().toString());
    ok = ok && DisplayRenderer.dirToArrow("S").equals(0x2191.toChar().toString());
    ok = ok && DisplayRenderer.dirToArrow("W").equals(0x2192.toChar().toString());
    logger.debug("cardinals ok=" + ok);
    return ok;
}

(:test)
function testDirToArrowIntercardinals(logger as Test.Logger) as Boolean {
    // All 4 intercardinal directions: NE→↙, SE→↖, SW→↗, NW→↘
    var ok = true;
    ok = ok && DisplayRenderer.dirToArrow("NE").equals(0x2199.toChar().toString());
    ok = ok && DisplayRenderer.dirToArrow("SE").equals(0x2196.toChar().toString());
    ok = ok && DisplayRenderer.dirToArrow("SW").equals(0x2197.toChar().toString());
    ok = ok && DisplayRenderer.dirToArrow("NW").equals(0x2198.toChar().toString());
    logger.debug("intercardinals ok=" + ok);
    return ok;
}

(:test)
function testDirToArrowPassthrough(logger as Test.Logger) as Boolean {
    // Unknown labels pass through unchanged
    var result = DisplayRenderer.dirToArrow("?");
    logger.debug("dirToArrow(?) = '" + result + "'");
    return result.equals("?");
}

(:test)
function testRenderWindSlotArrowMode(logger as Test.Logger) as Boolean {
    DisplayRenderer.useArrows = true;
    var data = new WindData("2025-01-01T12:00:00Z", 4, 7, "SW");
    var result = DisplayRenderer.renderWindSlot(data);
    DisplayRenderer.useArrows = false;
    logger.debug("renderWindSlot arrow SW = '" + result + "'");
    // SW wind → ↗ (U+2197)
    return result.equals("4/7" + 0x2197.toChar().toString());
}

(:test)
function testRenderWindSlotLabelMode(logger as Test.Logger) as Boolean {
    DisplayRenderer.useArrows = false;
    var data = new WindData("2025-01-01T12:00:00Z", 4, 7, "SW");
    var result = DisplayRenderer.renderWindSlot(data);
    logger.debug("renderWindSlot label SW = '" + result + "'");
    return result.equals("4/7SW");
}

// ── WindData ──────────────────────────────────────────────────────────

(:test)
function testWindDataInit(logger as Test.Logger) as Boolean {
    var wd = new WindData("2025-06-15T09:00:00Z", 5, 12, "SE");
    logger.debug("time=" + wd.time + " ws=" + wd.windSpeed + " gs=" + wd.gustSpeed + " dir=" + wd.windDir);
    return wd.time.equals("2025-06-15T09:00:00Z") &&
           wd.windSpeed == 5 &&
           wd.gustSpeed == 12 &&
           wd.windDir.equals("SE");
}
