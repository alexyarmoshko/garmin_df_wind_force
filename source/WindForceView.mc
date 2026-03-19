import Toybox.Activity;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

class WindForceView extends WatchUi.DataField {

    // Number of time slots that fit in the current field width
    private var _slots as Number = 1;
    private var _fetchMgr as FetchManager;

    // Custom BMFont resources for arrows display mode (lg > md > sm)
    private var _WindForceFontLg as Graphics.FontType?;
    private var _WindForceFontMd as Graphics.FontType?;
    private var _WindForceFontSm as Graphics.FontType?;

    (:typecheck(false))
    function initialize() {
        DataField.initialize();
        _fetchMgr = new FetchManager();
        DisplayRenderer.init();
        _WindForceFontLg = WatchUi.loadResource($.Rez.Fonts.WindForceFontL);
        _WindForceFontMd = WatchUi.loadResource($.Rez.Fonts.WindForceFontM);
        _WindForceFontSm = WatchUi.loadResource($.Rez.Fonts.WindForceFontS);
    }

    function onLayout(dc as Dc) as Void {
        _slots = DisplayRenderer.slotCount(dc.getWidth());
    }

    function compute(info as Activity.Info) as Void {
        _fetchMgr.updatePosition(info);

        if (_fetchMgr.gpsJustAcquired) {
            _fetchMgr.gpsJustAcquired = false;
            scheduleImmediateFetch();
        }
    }

    //! Schedule a background fetch at the earliest time Garmin allows.
    //! Replaces the active Duration registration with a one-shot Moment.
    //! The repeating schedule is restored in onBackgroundData().
    private function scheduleImmediateFetch() as Void {
        var lastTime = Background.getLastTemporalEventTime();
        if (lastTime != null) {
            // Schedule at lastTime + 5 min. If that moment is in the
            // past, the event fires immediately.
            Background.registerForTemporalEvent(
                (lastTime as Time.Moment).add(new Time.Duration(5 * 60)));
        } else {
            // No prior event in this session — fire immediately.
            Background.registerForTemporalEvent(Time.now());
        }
    }

    //! Reset all session state: cache, GPS keys, and FetchManager flags.
    //! Called from both onTimerReset() and onBackgroundData(session_end).
    function resetSession() as Void {
        StorageManager.clearAllForecasts();
        Storage.deleteValue("bg_lat");
        Storage.deleteValue("bg_lon");
        _fetchMgr.hasPosition = false;
        _fetchMgr.gpsJustAcquired = false;
    }

    //! Foreground safety net for activity-end cache cleanup.
    //! Fires when the activity timer is reset at the end of a session.
    function onTimerReset() as Void {
        resetSession();
        Background.deleteTemporalEvent();
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        // Read display-only direction setting (0=Labels, 1=Arrows)
        var dirSetting = Application.Properties.getValue("windDirection");
        DisplayRenderer.useArrows = (dirSetting instanceof Number && dirSetting == 1);

        var bgColor = getBackgroundColor();
        var fgColor = (bgColor == Graphics.COLOR_WHITE) ?
            Graphics.COLOR_BLACK : Graphics.COLOR_WHITE;

        dc.setColor(fgColor, bgColor);
        dc.clear();

        // Load forecast data from storage for current position
        var dict = findBestForecast();

        // Use per-forecast fetch timestamp for staleness (not global)
        var ts = 0;
        if (dict != null) {
            var fetchTs = (dict as Dictionary)["fetch_ts"];
            if (fetchTs instanceof Number) { ts = fetchTs as Number; }
        }

        // Try rendering with max slots, reduce if text overflows
        var maxWidth = dc.getWidth() - 4;
        var slots = _slots;
        var text = "";
        var font = selectBuiltInFontSize(dc, "");
        var useCustomFontFamily = shouldUseCustomFontFamily();
        DisplayRenderer.useCustomGlyphPlaceholders = useCustomFontFamily;
        while (slots > 0) {
            var forecasts = parseForecastEntries(dict, slots);
            text = DisplayRenderer.formatLayout(forecasts, ts, _fetchMgr.hasPosition, slots);
            font = selectFontSize(dc, text, useCustomFontFamily);
            if (dc.getTextWidthInPixels(text, font) <= maxWidth) {
                break;
            }
            slots--;
        }

        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            dc.getWidth() / 2,
            dc.getHeight() / 2,
            font,
            text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    //! Parse forecast entries from a stored forecast dictionary.
    //! @param dict The forecast dictionary from storage (may be null)
    //! @param slots Maximum number of slots to parse
    private function parseForecastEntries(dict as Dictionary?, slots as Number) as Array<WindData> {
        var result = [] as Array<WindData>;

        if (dict == null) {
            return result;
        }

        var forecasts = (dict as Dictionary)["forecasts"];
        if (!(forecasts instanceof Array)) {
            return result;
        }

        var arr = forecasts as Array;
        var count = (arr.size() < slots) ? arr.size() : slots;
        for (var i = 0; i < count; i++) {
            var entry = arr[i];
            if (entry instanceof Dictionary) {
                var d = entry as Dictionary;
                var ws = d["wind_speed"];
                var gs = d["gust_speed"];
                var wd = d["wind_dir"];
                result.add(new WindData(
                    (d["time"] instanceof String) ? d["time"] as String : "",
                    (ws instanceof Number) ? ws as Number : 0,
                    (gs instanceof Number) ? gs as Number : 0,
                    (wd instanceof String) ? wd as String : "?"
                ));
            }
        }

        return result;
    }

    //! Find the best available forecast dictionary from storage.
    //! Uses current GPS position: tries exact rounded match first,
    //! then falls back to nearest cached grid point within 2.5 km.
    //! Returns null when no GPS fix — avoids showing stale data from
    //! a previous session or location.
    private function findBestForecast() as Dictionary? {
        if (!_fetchMgr.hasPosition) {
            return null;
        }

        var latDeg = _fetchMgr.currentLatDeg;
        var lonDeg = _fetchMgr.currentLonDeg;

        // Try exact rounded coordinate match
        var rLat = GeoUtils.roundCoord(latDeg);
        var rLon = GeoUtils.roundCoord(lonDeg);
        var exact = StorageManager.loadForecast(rLat, rLon);
        if (exact != null) {
            return exact;
        }

        // Fall back to nearest cached grid point within 2.5 km
        return StorageManager.loadNearestForecast(latDeg, lonDeg);
    }

    //! Decide whether to use the custom BMFont family or built-in Garmin fonts.
    //! The custom font only contains digits, punctuation, bullets, and arrows,
    //! so "NO GPS" must always use the built-in font family.
    private function shouldUseCustomFontFamily() as Boolean {
        return DisplayRenderer.useArrows && _fetchMgr.hasPosition;
    }

    //! Select the largest font size within the chosen family that fits the field.
    private function selectFontSize(
        dc as Dc,
        text as String,
        useCustomFontFamily as Boolean
    ) as Graphics.FontType {
        if (useCustomFontFamily) {
            return selectCustomFontSize(dc, text);
        }
        return selectBuiltInFontSize(dc, text);
    }

    //! Select the largest custom BMFont size whose text width fits the field.
    private function selectCustomFontSize(dc as Dc, text as String) as Graphics.FontType {
        var maxWidth = dc.getWidth() - 4; // 2px padding each side

        if (_WindForceFontLg != null && dc.getTextWidthInPixels(text, _WindForceFontLg) <= maxWidth) {
            return _WindForceFontLg as Graphics.FontType;
        }
        if (_WindForceFontMd != null && dc.getTextWidthInPixels(text, _WindForceFontMd) <= maxWidth) {
            return _WindForceFontMd as Graphics.FontType;
        }
        return (_WindForceFontSm != null) ? _WindForceFontSm : Graphics.FONT_XTINY;
    }

    //! Select the largest built-in Garmin font whose text width fits the field.
    private function selectBuiltInFontSize(dc as Dc, text as String) as Graphics.FontType {
        var maxWidth = dc.getWidth() - 4; // 2px padding each side

        var fonts = [
            Graphics.FONT_LARGE,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
        ];
        for (var i = 0; i < fonts.size() - 1; i++) {
            if (dc.getTextWidthInPixels(text, fonts[i]) <= maxWidth) {
                return fonts[i];
            }
        }
        return fonts[fonts.size() - 1];
    }

}
