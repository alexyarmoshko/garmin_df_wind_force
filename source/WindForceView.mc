import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class WindForceView extends WatchUi.DataField {

    // Number of time slots that fit in the current field width
    private var _slots as Number = 1;

    // Hardcoded sample data for pre-Milestone 4 validation.
    // Simulates proxy response: pre-converted Beaufort values, cardinal labels, veer/back.
    // Renders as "3(4)NE>5(6)S<3(5)SW" in 3-slot layout.
    private var _sampleData as Array<WindData> = [
        new WindData("2026-03-13T10:00:00Z", 3, 4, "NE", null),
        new WindData("2026-03-13T13:00:00Z", 5, 6, "S",  ">"),
        new WindData("2026-03-13T16:00:00Z", 3, 5, "SW", "<")
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

        // Show only as many entries as the slot count allows
        var data = _sampleData.slice(0, _slots);
        var text = DisplayRenderer.formatLayout(data, 0);

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
