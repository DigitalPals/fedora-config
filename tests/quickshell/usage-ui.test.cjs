const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

const popover = fs.readFileSync(
    path.join(shellDir, "Popovers", "UsagePopover.qml"), "utf8");
const usage = fs.readFileSync(
    path.join(shellDir, "Common", "Usage.qml"), "utf8");

test("model usage no longer collects or renders usage history", () => {
    assert.doesNotMatch(popover, /histMode|histBars|USAGE HISTORY/);
    assert.doesNotMatch(usage,
        /property var history|recordSamples|histBars|quickshell-usage-history/);
});

test("model-specific quota periods render in full on their own line", () => {
    assert.ok(popover.includes(
        'return `${m[1]}\\n${m[2].replace(" ", "-")} usage`.toUpperCase();'));
    assert.match(popover,
        /id:\s*cardLabel[\s\S]{0,600}?wrapMode:\s*Text\.Wrap/);
});

test("usage cards contain their content on padded tile backgrounds", () => {
    assert.match(popover,
        /id:\s*card[\s\S]{0,700}?color:\s*Theme\.tile[\s\S]{0,100}?border\.color:\s*Theme\.hairlineSoft/);
    assert.match(popover,
        /id:\s*resetCol[\s\S]{0,700}?"resets in " \+ Usage\.formatReset[\s\S]{0,500}?Usage\.formatResetAbs/,
        "relative and absolute reset times should occupy separate contained rows");
});
