const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

// The T3-integrated composer keeps controls in one glass shell. These pins
// prevent the round send action and access chip from regressing into tall form
// controls when the shell-wide metrics change.

const composer = fs.readFileSync(
    path.join(shellDir, "Popovers/T3Composer.qml"), "utf8");

test("T3 composer send button is a round inline action, not a form control", () => {
    const send = composer.match(
        /Rectangle\s*\{\s*id:\s*sendButton\b([\s\S]*?)\n\s*Sym\s*\{/);

    assert.ok(send, "expected to find the composer's send button");
    assert.match(send[1], /height:\s*Theme\.inlineActionHeight\b/,
        "the send button sits inside the prompt box and must stay pill-sized");
    assert.doesNotMatch(send[1], /Theme\.controlHeight\b/,
        "a form-control height fills the prompt box");
    assert.match(send[1], /width:\s*Theme\.inlineActionHeight\b/);
    assert.match(send[1], /radius:\s*width \/ 2\b/,
        "the primary composer action should keep T3's circular silhouette");
});

test("T3 composer access chip fits inside the settings row", () => {
    const chip = composer.match(
        /Rectangle\s*\{\s*id:\s*accessChip\b([\s\S]*?)\n\s*Text\s*\{/);

    assert.ok(chip, "expected to find the run-settings access chip");
    assert.match(chip[1], /height:\s*Theme\.chipInnerHeight\b/,
        "the chip is centred in a controlHeight row and must be shorter than it");
    assert.doesNotMatch(chip[1], /Theme\.controlHeight\b/,
        "a chip as tall as its row overflows it when centred on the chevron");
});

test("T3 composer preserves the Ultrathink prompt cue inside the glass shell", () => {
    assert.match(composer,
        /readonly property bool ultrathink:\s*\/\\bultrathink\\b\/i\.test\(promptEdit\.text\)/);
    assert.match(composer,
        /visible:\s*root\.ultrathink[\s\S]*?color:\s*T3Theme\.accentSubtle/);
});

test("draft feedback waits for the selected-draft binding before resyncing input", () => {
    const connections = composer.match(
        /Connections\s*\{\s*target:\s*T3Code([\s\S]*?)\n\s*}/);

    assert.ok(connections, "expected composer draft connections");
    assert.match(composer,
        /id:\s*promptSyncTimer[\s\S]*?interval:\s*0[\s\S]*?onTriggered:\s*root\.syncPrompt\(\)/);
    assert.match(connections[1], /promptSyncTimer\.restart\(\)/);
    assert.doesNotMatch(connections[1], /root\.syncPrompt\(\)/,
        "a synchronous resync can read the previous draft and undo the keystroke");
});

test("the header glyph button lives in IconButton.qml, not inline copies", () => {
    for (const page of ["Popovers/T3ThreadPage.qml", "Popovers/T3NewThreadPage.qml"]) {
        const source = fs.readFileSync(path.join(shellDir, page), "utf8");
        assert.doesNotMatch(source, /component\s+(IconButton|HeaderAction)\s*:/,
            `${page} must use the shared IconButton type instead of a local copy`);
    }
});
