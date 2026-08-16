const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

test("T3 picker choices use the dense floating-menu surface", () => {
    const source = fs.readFileSync(
        path.join(shellDir, "Popovers/T3Picker.qml"), "utf8");
    const menu = source.match(
        /Rectangle\s*\{\s*id:\s*menu\b([\s\S]*?)\n\s*Flickable\s*\{/);

    assert.ok(menu, "expected to find the T3 picker's menu panel");
    assert.match(menu[1], /color:\s*Theme\.glassMenu\b/,
        "choices must obscure the composer controls painted underneath them");
    assert.doesNotMatch(menu[1], /color:\s*Theme\.insetSurface\b/,
        "the recessed tile fill is too transparent for a floating menu");
});
