const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

test("T3 picker choices use the dense product-local overlay surface", () => {
    const source = fs.readFileSync(
        path.join(shellDir, "Popovers/T3Picker.qml"), "utf8");
    const menu = source.match(
        /Rectangle\s*\{\s*id:\s*menu\b([\s\S]*?)\n\s*Flickable\s*\{/);

    assert.ok(menu, "expected to find the T3 picker's menu panel");
    assert.match(menu[1], /color:\s*T3Theme\.overlay\b/,
        "choices must obscure the composer controls painted underneath them");
    assert.doesNotMatch(menu[1], /color:\s*Theme\.(?:surfaceMenu|insetSurface)\b/,
        "T3 floating menus must not fall back to wallpaper-derived shell surfaces");
    assert.match(source, /event\.key >= Qt\.Key_1 && event\.key <= Qt\.Key_9/,
        "the displayed option numbers must be actionable shortcuts");
});
