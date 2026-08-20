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

test("inline actions fit inside a full T3 work row while parked rows stay compact", () => {
    const theme = read("Common/Theme.qml");
    const t3Theme = read("Common/T3Theme.qml");
    const action = read("Popovers/ActionButton.qml");
    const inbox = read("Popovers/T3InboxPage.qml");

    assert.match(action, /height:\s*Theme\.inlineActionHeight/,
        "shared inline actions must not inherit the full-size form control height");

    const actionHeight = intToken(theme, "inlineActionHeight");
    const secondaryText = intToken(theme, "fontSecondary");
    const activeRowHeight = intToken(t3Theme, "activeRowHeight");
    const quietRowHeight = intToken(t3Theme, "quietRowHeight");

    assert.ok(actionHeight + 2 + secondaryText <= activeRowHeight - 8,
        "inline actions leave too little room for the active row's project line");
    assert.ok(quietRowHeight < activeRowHeight,
        "settled and snoozed rows must remain visibly denser than active work");
    assert.match(inbox,
        /height:\s*entry\.compact \? T3Theme\.quietRowHeight : T3Theme\.activeRowHeight/);
});
