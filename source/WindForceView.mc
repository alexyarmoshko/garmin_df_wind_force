import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class WindForceView extends WatchUi.DataField {

    // Number of time slots that fit in the current field width
    private var _slots as Number = 1;
    private var _fetchMgr as FetchManager;

    function initialize() {
        DataField.initialize();
        _fetchMgr = new FetchManager();
        DisplayRenderer.init();
    }

    function onLayout(dc as Dc) as Void {
        _slots = DisplayRenderer.slotCount(dc.getWidth());
    }

    function compute(info as Activity.Info) as Void {
        _fetchMgr.updatePosition(info);
    }

    function onUpdate(dc as Dc) as Void {
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
        var font = Graphics.FONT_XTINY;
        while (slots > 0) {
            var forecasts = parseForecastEntries(dict, slots);
            text = DisplayRenderer.formatLayout(forecasts, ts, _fetchMgr.hasPosition);
            font = selectFont(dc, text);
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

    //! Select the largest font whose text width fits the field.
    private function selectFont(dc as Dc, text as String) as FontDefinition {
        var fonts = [
            Graphics.FONT_LARGE,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
        ];
        var maxWidth = dc.getWidth() - 4; // 2px padding each side
        for (var i = 0; i < fonts.size() - 1; i++) {
            if (dc.getTextWidthInPixels(text, fonts[i]) <= maxWidth) {
                return fonts[i];
            }
        }
        return fonts[fonts.size() - 1];
    }

}
