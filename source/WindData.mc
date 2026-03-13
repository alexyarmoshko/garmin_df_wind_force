import Toybox.Lang;

class WindData {
    var time as String;
    var windMps as Float;
    var windDeg as Number;
    var windBeaufort as Number;
    var gustMps as Float;

    function initialize(
        time as String,
        windMps as Float,
        windDeg as Number,
        windBeaufort as Number,
        gustMps as Float
    ) {
        self.time = time;
        self.windMps = windMps;
        self.windDeg = windDeg;
        self.windBeaufort = windBeaufort;
        self.gustMps = gustMps;
    }
}
