import Toybox.Lang;

class WindData {
    var time as String;
    var windSpeed as Number;      // pre-converted integer in the requested unit
    var gustSpeed as Number;      // pre-converted integer in the same unit
    var windDir as String;        // cardinal/intercardinal label (e.g., "NE")

    function initialize(
        time as String,
        windSpeed as Number,
        gustSpeed as Number,
        windDir as String
    ) {
        self.time = time;
        self.windSpeed = windSpeed;
        self.gustSpeed = gustSpeed;
        self.windDir = windDir;
    }
}
