const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

const notificationCenter = fs.readFileSync(
    path.join(shellDir, "Popovers", "NotifCenterPopover.qml"), "utf8");

test("notification-centre forecast icons retain their weather colours", () => {
    assert.match(notificationCenter,
        /color:\s*Weather\.glyphColor\(forecastDay\.modelData\.code,\s*true\)/,
        "forecast marks must use the condition palette instead of a neutral text tint");
});

test("notification-centre forecast days share all remaining card width", () => {
    assert.match(notificationCenter,
        /id:\s*forecastRow[\s\S]*?width:\s*parent\.width\s*-\s*currentWeather\.width\s*-\s*weatherDivider\.width[\s\S]*?-\s*parent\.spacing\s*\*\s*2/,
        "the forecast row must consume the space after the current conditions");
    assert.match(notificationCenter,
        /readonly property real dayWidth:\s*width\s*\/\s*Math\.max\(1,\s*forecastRepeater\.count\)/,
        "the forecast row must derive one equal-width lane per available day");
    assert.match(notificationCenter, /width:\s*forecastRow\.dayWidth/,
        "each forecast delegate must occupy its whole lane");
});
