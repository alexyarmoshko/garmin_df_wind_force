import Toybox.Activity;
import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Time;
import Toybox.WatchUi;

class WindForceView extends WatchUi.DataField {

    // Number of time slots that fit in the current field width
    private var _slots as Number = 1;
    private var _fetchMgr as FetchManager;

    function initialize() {
        DataField.initialize();
        _fetchMgr = new FetchManager();
    }

    function onLayout(dc as Dc) as Void {
        _slots = DisplayRenderer.slotCount(dc.getWidth());
        _fetchMgr.setSlotCount(_slots);
    }

    function compute(info as Activity.Info) as Void {
        _fetchMgr.executeFetchCycle(info);
    }

    function onUpdate(dc as Dc) as Void {
        var bgColor = getBackgroundColor();
        var fgColor = (bgColor == Graphics.COLOR_WHITE) ?
            Graphics.COLOR_BLACK : Graphics.COLOR_WHITE;

        dc.setColor(fgColor, bgColor);
        dc.clear();

        // Load forecast data from storage for current position
        var forecasts = loadCurrentForecasts();
        var fetchTs = Storage.getValue("last_fetch_ts");
        var ts = (fetchTs instanceof Number) ? fetchTs as Number : 0;

        var text = DisplayRenderer.formatLayout(forecasts, ts);

        var font = selectFont(dc, text);

        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            dc.getWidth() / 2,
            dc.getHeight() / 2,
            font,
            text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    //! Load forecasts for the current position from storage.
    //! Falls back to nearest cached forecast if exact match unavailable.
    private function loadCurrentForecasts() as Array<WindData> {
        var result = [] as Array<WindData>;

        // Try to find forecast data in storage
        var dict = findBestForecast();
        if (dict == null) {
            return result;
        }

        var forecasts = dict["forecasts"];
        if (!(forecasts instanceof Array)) {
            return result;
        }

        var arr = forecasts as Array;
        var count = (arr.size() < _slots) ? arr.size() : _slots;
        for (var i = 0; i < count; i++) {
            var entry = arr[i];
            if (entry instanceof Dictionary) {
                var d = entry as Dictionary;
                var ws = d["wind_speed"];
                var gs = d["gust_speed"];
                var wd = d["wind_dir"];
                var v = d["veer"];
                result.add(new WindData(
                    (d["time"] instanceof String) ? d["time"] as String : "",
                    (ws instanceof Number) ? ws as Number : 0,
                    (gs instanceof Number) ? gs as Number : 0,
                    (wd instanceof String) ? wd as String : "?",
                    (v instanceof String) ? v as String : null
                ));
            }
        }

        return result;
    }

    //! Find the best available forecast dictionary from storage.
    //! Uses current GPS position: tries exact rounded match first,
    //! then falls back to nearest cached grid point within 2.5 km.
    private function findBestForecast() as Dictionary? {
        if (!_fetchMgr.hasPosition) {
            // No GPS yet — try last stored entry as fallback
            var keys = StorageManager.getStoredKeys();
            if (keys.size() > 0) {
                var val = Storage.getValue(keys[keys.size() - 1]);
                if (val instanceof Dictionary) {
                    return val as Dictionary;
                }
            }
            return null;
        }

        var latDeg = _fetchMgr.currentLatDeg;
        var lonDeg = _fetchMgr.currentLonDeg;

        // Try exact rounded coordinate match
        var rLat = StorageManager.roundCoord(latDeg);
        var rLon = StorageManager.roundCoord(lonDeg);
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
