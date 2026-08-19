const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

function read(rel) {
    return fs.readFileSync(path.join(shellDir, rel), "utf8");
}

function intToken(source, name) {
    const match = source.match(new RegExp(
        `readonly property int ${name}:\\s*(\\d+)`));
    assert.ok(match, `Theme.${name} must remain a literal integer token`);
    return Number(match[1]);
}

test("inline action pills fit beside a T3 inbox tile's second line", () => {
    const theme = read("Common/Theme.qml");
    const action = read("Popovers/ActionButton.qml");

    assert.match(action, /height:\s*Theme\.inlineActionHeight/,
        "shared inline actions must not inherit the full-size form control height");

    const actionHeight = intToken(theme, "inlineActionHeight");
    const secondaryText = intToken(theme, "fontSecondary");
    const tileHeight = intToken(theme, "tileHeight");

    // T3InboxPage stacks the revealed action/title line, 3px of spacing, and
    // a secondary project line inside one tile. Keep room for font leading as
    // well as the declared pixel sizes; the old 46px control left -2px before
    // leading and visibly pushed that second line through the card edge.
    assert.ok(actionHeight + 3 + secondaryText <= tileHeight - 8,
        "inline actions leave too little room for the T3 tile's project line");
});
