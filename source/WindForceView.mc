import Toybox.Activity;
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

    // Cached state — avoids Storage/Properties reads and object
    // allocations on every 1-second onUpdate() tick.
    private var _cacheValid as Boolean = false;
    private var _cachedDict as Dictionary? = null;
    private var _cachedForecasts as Array<WindData> = [] as Array<WindData>;
    // Last position used to build the cache (degrees).
    // Cache is invalidated when the device moves to a different grid cell.
    private var _lastCachedLat as Double = 0.0d;
    private var _lastCachedLon as Double = 0.0d;

    // Cached display output — avoids string concatenation and font
    // fitting on every tick. Rebuilt only on data change, slot change,
    // or staleness transition.
    private var _displayValid as Boolean = false;
    private var _displayText as String = "";
    private var _displayFont as Graphics.FontType = Graphics.FONT_XTINY;
    private var _wasStale as Boolean = false;

    // Set by selectBuiltInFontSize to indicate whether the returned
    // font actually fits the field width.
    private var _fontFits as Boolean = false;

    (:typecheck(false))
    function initialize() {
        DataField.initialize();
        _fetchMgr = new FetchManager();
        DisplayRenderer.init();
    }

    function onLayout(dc as Dc) as Void {
        var newSlots = DisplayRenderer.slotCount(dc.getWidth());
        if (newSlots != _slots) {
            _slots = newSlots;
            _cacheValid = false;
        }
    }

    function compute(info as Activity.Info) as Void {
        var hadPosition = _fetchMgr.hasPosition;
        _fetchMgr.updatePosition(info);

        if (_fetchMgr.gpsJustAcquired) {
            _fetchMgr.gpsJustAcquired = false;
            _cacheValid = false;
            scheduleImmediateFetch();
        } else if (hadPosition && !_fetchMgr.hasPosition) {
            // GPS fix lost
            _cacheValid = false;
        }

        // Invalidate when position moves to a different grid cell
        // (half grid step = 0.0125 deg ~ 1.4 km)
        if (_fetchMgr.hasPosition) {
            var dLat = _fetchMgr.currentLatDeg - _lastCachedLat;
            var dLon = _fetchMgr.currentLonDeg - _lastCachedLon;
            if (dLat > 0.0125 || dLat < -0.0125 ||
                dLon > 0.0125 || dLon < -0.0125) {
                _cacheValid = false;
            }
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
        _cacheValid = false;
    }

    //! Foreground safety net for activity-end cache cleanup.
    //! Fires when the activity timer is reset at the end of a session.
    function onTimerReset() as Void {
        resetSession();
        Background.deleteTemporalEvent();
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var bgColor = getBackgroundColor();
        var fgColor = (bgColor == Graphics.COLOR_WHITE) ?
            Graphics.COLOR_BLACK : Graphics.COLOR_WHITE;

        dc.setColor(fgColor, bgColor);
        dc.clear();

        // Rebuild cached forecast data only when invalidated
        if (!_cacheValid) {
            _cachedDict = findBestForecast();
            _cachedForecasts = parseForecastEntries(_cachedDict, _slots);
            _lastCachedLat = _fetchMgr.currentLatDeg;
            _lastCachedLon = _fetchMgr.currentLonDeg;
            _cacheValid = true;
            _displayValid = false; // data changed → must rebuild text
        }

        // Check staleness transition (cheap — no Storage access)
        var fetchTs = 0;
        if (_cachedDict != null) {
            var ft = (_cachedDict as Dictionary)["fetch_ts"];
            if (ft instanceof Number) {
                fetchTs = ft as Number;
            }
        }
        var isStale = (fetchTs > 0 && (Time.now().value() - fetchTs) > STALE_THRESHOLD_SEC);
        if (isStale != _wasStale) {
            _wasStale = isStale;
            _displayValid = false;
        }

        // Rebuild display text and font only when needed
        if (!_displayValid) {
            var maxWidth = dc.getWidth() - 4;
            var slots = _slots;
            var text = "";
            // Default to smallest font
            var font = Graphics.FONT_XTINY;

            while (slots > 0) {
                text = DisplayRenderer.formatLayout(
                    _cachedForecasts,
                    isStale,
                    _fetchMgr.hasPosition,
                    slots
                );
                font = selectBuiltInFontSize(dc, text, maxWidth);
                if (_fontFits) {
                    break;
                }
                slots--;
            }
            _displayText = text;
            _displayFont = font;
            _displayValid = true;
        }

        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            dc.getWidth() / 2,
            dc.getHeight() / 2,
            _displayFont,
            _displayText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    //! Invalidate cached forecast data. Called when new background data
    //! arrives or storage is cleared externally.
    function invalidateCache() as Void {
        _cacheValid = false;
    }

    //! Called by WindForceApp when settings change.
    //! Invalidates forecast cache.
    function onAppSettingsChanged() as Void {
        _cacheValid = false;
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

    //! Select the largest built-in Garmin font whose text width fits the field.
    private function selectBuiltInFontSize(
        dc as Dc,
        text as String,
        maxWidth as Number
    ) as Graphics.FontType {
        var fonts = [
            Graphics.FONT_LARGE,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
        ];
        for (var i = 0; i < fonts.size(); i++) {
            if (dc.getTextWidthInPixels(text, fonts[i]) <= maxWidth) {
                _fontFits = true;
                return fonts[i];
            }
        }
        _fontFits = false;
        return fonts[fonts.size() - 1];
    }

}
