pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Open-Meteo backed weather state for the bar chip + popover. No API key;
// coordinates are fixed here (QS_WEATHER_LAT/LON/PLACE override them).
Singleton {
    id: root

    readonly property string latitude: Quickshell.env("QS_WEATHER_LAT") || "52.78"
    readonly property string longitude: Quickshell.env("QS_WEATHER_LON") || "6.90"
    readonly property string place: Quickshell.env("QS_WEATHER_PLACE") || "Emmen"

    readonly property int pollIntervalSecs: 1200

    property bool ready: false
    property double updatedAt: 0
    property int temp: 0
    property int feels: 0
    property int humidity: 0
    property int windKmh: 0
    property string windDir: ""
    property string condition: ""
    property int code: -1
    property bool isDay: true
    // [{ day, code, lo, hi }] — today plus four days out.
    property var days: []

    readonly property string url: "https://api.open-meteo.com/v1/forecast"
        + "?latitude=" + latitude + "&longitude=" + longitude
        + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day"
        + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
        + "&timezone=auto&forecast_days=5"

    function describe(code) {
        if (code === 0)
            return "Clear sky";
        if (code === 1)
            return "Mostly clear";
        if (code === 2)
            return "Partly cloudy";
        if (code === 3)
            return "Overcast";
        if (code === 45 || code === 48)
            return "Fog";
        if (code >= 51 && code <= 57)
            return "Drizzle";
        if (code >= 61 && code <= 67)
            return "Rain";
        if (code >= 71 && code <= 77)
            return "Snow";
        if (code >= 80 && code <= 82)
            return "Rain showers";
        if (code === 85 || code === 86)
            return "Snow showers";
        if (code >= 95)
            return "Thunderstorm";
        return "—";
    }

    // Nerd Font weather set (nf-weather, U+E30x–U+E37x). Clear and lightly
    // clouded skies get a day/night variant; everything else reads the same
    // either way.
    function glyph(code, day) {
        if (code < 0)
            return ""; // na
        if (code === 0)
            return day ? "" : ""; // day_sunny / night_clear
        if (code === 1 || code === 2)
            return day ? "" : ""; // day_cloudy / night_alt_cloudy
        if (code === 3)
            return ""; // cloudy
        if (code === 45 || code === 48)
            return ""; // fog
        if (code >= 51 && code <= 57)
            return ""; // sprinkle
        if (code >= 61 && code <= 67)
            return ""; // rain
        if (code >= 71 && code <= 77)
            return ""; // snow
        if (code >= 80 && code <= 82)
            return ""; // showers
        if (code === 85 || code === 86)
            return ""; // snow
        if (code >= 95)
            return ""; // thunderstorm
        return "";
    }

    // Kept in the same code order as glyph() so an icon and its tint never
    // disagree about what the sky is doing.
    function glyphColor(code, day) {
        if (code < 0)
            return Theme.textDim;
        if (code <= 2)
            return day ? Theme.wxSun : Theme.wxMoon;
        if (code === 3)
            return Theme.wxCloud;
        if (code === 45 || code === 48)
            return Theme.wxFog;
        if (code >= 51 && code <= 67)
            return Theme.wxRain;
        if (code >= 71 && code <= 77)
            return Theme.wxSnow;
        if (code >= 80 && code <= 82)
            return Theme.wxRain;
        if (code === 85 || code === 86)
            return Theme.wxSnow;
        if (code >= 95)
            return Theme.wxStorm;
        return Theme.textDim;
    }

    function compass(deg) {
        return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(deg / 45) % 8];
    }

    function apply(text) {
        if (text.trim() === "")
            return;
        try {
            const d = JSON.parse(text);
            const cur = d.current;
            temp = Math.round(cur.temperature_2m);
            feels = Math.round(cur.apparent_temperature);
            humidity = Math.round(cur.relative_humidity_2m);
            windKmh = Math.round(cur.wind_speed_10m);
            windDir = compass(cur.wind_direction_10m);
            code = cur.weather_code;
            isDay = cur.is_day === 1;
            condition = describe(cur.weather_code);
            const out = [];
            for (let i = 0; i < d.daily.time.length; i++) {
                out.push({
                    day: new Date(d.daily.time[i] + "T12:00:00").toLocaleDateString(Qt.locale("en_US"), "ddd"),
                    code: d.daily.weather_code[i],
                    lo: Math.round(d.daily.temperature_2m_min[i]),
                    hi: Math.round(d.daily.temperature_2m_max[i])
                });
            }
            days = out;
            updatedAt = Date.now();
            ready = true;
        } catch (e) {
            console.warn("weather parse failed:", e);
        }
    }

    function refresh() {
        fetchProc.running = false;
        fetchProc.running = true;
    }

    Process {
        id: fetchProc
        command: ["curl", "-sf", "--max-time", "15", root.url]
        stdout: StdioCollector {
            onStreamFinished: root.apply(text)
        }
    }

    Timer {
        interval: root.pollIntervalSecs * 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    // Retry quickly until the first fetch lands (Wi-Fi may still be
    // associating at session start).
    Timer {
        interval: 30000
        running: !root.ready
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
