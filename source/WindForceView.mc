import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class WindForceView extends WatchUi.DataField {

    // Number of time slots that fit in the current field width
    private var _slots as Number = 1;

    // Hardcoded sample data for Milestone 3 validation.
    // Matches the requirements examples: 3(4)NE, 5(6)S, 3(5)SW
    private var _sampleData as Array<WindData> = [
        new WindData("2026-03-13T10:00:00Z", 3.4f,  45, 3, 5.5f),   // ~3 Bft, gust ~4 Bft, NE
        new WindData("2026-03-13T13:00:00Z", 9.0f, 180, 5, 11.0f),  // ~5 Bft, gust ~6 Bft, S
        new WindData("2026-03-13T16:00:00Z", 3.4f, 225, 3, 8.5f)    // ~3 Bft, gust ~5 Bft, SW
    ];

    function initialize() {
        DataField.initialize();
    }

    function onLayout(dc as Dc) as Void {
        _slots = DisplayRenderer.slotCount(dc.getWidth());
    }

    function compute(info as Activity.Info) as Void {
    }

    function onUpdate(dc as Dc) as Void {
        var bgColor = getBackgroundColor();
        var fgColor = (bgColor == Graphics.COLOR_WHITE) ?
            Graphics.COLOR_BLACK : Graphics.COLOR_WHITE;

        dc.setColor(fgColor, bgColor);
        dc.clear();

        var text = DisplayRenderer.formatLayout(
            _sampleData, _slots, UNIT_BEAUFORT
        );

        // Pick the largest font that fits the available width
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
        return fonts[fonts.size() - 1]; // fallback to smallest
    }

}
