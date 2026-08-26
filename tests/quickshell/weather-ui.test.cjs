const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

const weather = fs.readFileSync(
    path.join(shellDir, "Popovers", "WeatherPopover.qml"), "utf8");

test("current conditions reserve a generous gap before the forecast", () => {
    assert.match(weather, /Surface\s*\{[\s\S]{0,160}?spacing:\s*Theme\.panelSectionSpacing/);
    assert.match(weather,
        /Current conditions[\s\S]{0,160}?height:\s*Theme\.controlHeight/);
});

test("standalone forecast icons retain their weather colours", () => {
    assert.match(weather,
        /color:\s*Weather\.glyphColor\(dayRow\.modelData\.code,\s*true\)/,
        "forecast marks must use the condition palette instead of a neutral text tint");
    assert.match(weather,
        /color:\s*Weather\.glyphColor\(Weather\.code,\s*Weather\.isDay\)/,
        "current conditions must preserve their day/night palette");
});

test("standalone forecast rows use the full card and a shared weekly scale", () => {
    assert.match(weather, /id:\s*forecastCol[\s\S]{0,100}?width:\s*parent\.width - 24/);
    assert.match(weather, /id:\s*dayRow[\s\S]{0,160}?width:\s*forecastCol\.width/);
    assert.match(weather,
        /width:\s*parent\.width - 56 - loHi\.implicitWidth - 8/,
        "the range meter must consume the lane between its glyph and temperatures");
    assert.match(weather,
        /dayRow\.modelData\.lo - root\.weekLo[\s\S]{0,120}?root\.weekSpan/,
        "every day's range must use the same weekly temperature span");
});
