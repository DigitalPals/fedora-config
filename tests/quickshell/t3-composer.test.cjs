const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

// The redesign grew Theme.controlHeight from 34 to 46 for standalone header,
// footer and form controls. The composer's inline elements were sized with it
// and inflated: a Send slab filling the prompt box, and an access chip taller
// than the settings row it sits in. These pins keep the inline tokens in place.

const composer = fs.readFileSync(
    path.join(shellDir, "Popovers/T3Composer.qml"), "utf8");

test("T3 composer send button is an inline pill, not a form control", () => {
    const send = composer.match(
        /Rectangle\s*\{\s*id:\s*sendButton\b([\s\S]*?)\n\s*Text\s*\{/);

    assert.ok(send, "expected to find the composer's send button");
    assert.match(send[1], /height:\s*Theme\.inlineActionHeight\b/,
        "the send button sits inside the prompt box and must stay pill-sized");
    assert.doesNotMatch(send[1], /Theme\.controlHeight\b/,
        "a form-control height fills the prompt box");
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

test("the header glyph button lives in IconButton.qml, not inline copies", () => {
    for (const page of ["Popovers/T3ThreadPage.qml", "Popovers/T3NewThreadPage.qml"]) {
        const source = fs.readFileSync(path.join(shellDir, page), "utf8");
        assert.doesNotMatch(source, /component\s+(IconButton|HeaderAction)\s*:/,
            `${page} must use the shared IconButton type instead of a local copy`);
    }
});
