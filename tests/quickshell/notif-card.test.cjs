const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

// The toast overlay and the notification centre drew the same card anatomy
// twice, ~180 lines each, and the copies had drifted. Common/NotifCard.qml is
// now the only one; each surface supplies its own `style` object because the
// two differ almost entirely in type, and typography.test.cjs pins that split
// per file.
//
// A `style` object is a plain `var`, so a missing key is `undefined` at
// runtime with nothing to catch it — not a parse error, not a qmllint
// warning, just a card that silently draws at size 0 or with no font. The
// main assertion below is therefore that every key NotifCard reads is one
// every caller supplies.

const CARD = path.join("Common", "NotifCard.qml");
const CALLERS = ["NotificationToasts.qml", path.join("Popovers", "NotifsPopover.qml")];

function read(rel) {
    return fs.readFileSync(path.join(shellDir, rel), "utf8");
}

// Keys the card actually reads, as `card.style.<key>`.
function keysRead() {
    return new Set([...read(CARD).matchAll(/\bcard\.style\.(\w+)/g)].map(m => m[1]));
}

// Keys a caller's `readonly property var cardStyle: ({ … })` supplies.
function keysSupplied(rel) {
    const source = read(rel);
    const start = source.indexOf("readonly property var cardStyle: ({");
    assert.notEqual(start, -1, `${rel} must declare a cardStyle object`);
    const open = source.indexOf("{", start);
    let depth = 0;
    let end = -1;
    for (let i = open; i < source.length; i++) {
        if (source[i] === "{") depth++;
        else if (source[i] === "}" && --depth === 0) { end = i; break; }
    }
    assert.notEqual(end, -1, `${rel}: cardStyle object is unterminated`);
    const body = source.slice(open + 1, end);
    return new Set([...body.matchAll(/^\s*(\w+):/gm)].map(m => m[1]));
}

test("the card anatomy is defined once, in Common/", () => {
    assert.ok(fs.existsSync(path.join(shellDir, CARD)));
    for (const rel of CALLERS) {
        const source = read(rel);
        // A local `component NotifCard`/`AppIcon`/`ActionPills` is how the
        // duplication looked before; re-adding one splits them again.
        assert.doesNotMatch(source, /component\s+(NotifCard|AppIcon|ActionPills)\s*:/,
            `${rel} redefines a card piece that Common/ already owns`);
    }
});

test("every style key the card reads is supplied by every caller", () => {
    const needed = keysRead();
    assert.ok(needed.size >= 10,
        `only found ${needed.size} style keys — has NotifCard stopped using card.style.*?`);
    for (const rel of CALLERS) {
        const supplied = keysSupplied(rel);
        const missing = [...needed].filter(key => !supplied.has(key)).sort();
        assert.deepEqual(missing, [], `${rel} leaves these style keys undefined`);
        const unused = [...supplied].filter(key => !needed.has(key)).sort();
        assert.deepEqual(unused, [], `${rel} supplies style keys nothing reads`);
    }
});

test("the two surfaces keep their own type, as typography.test.cjs requires", () => {
    // Not a restatement of that test: this one checks the split survives the
    // move into a shared card, which is the thing this refactor could break.
    const toast = keysSuppliedSource("NotificationToasts.qml");
    const centre = keysSuppliedSource(path.join("Popovers", "NotifsPopover.qml"));
    assert.match(toast, /face:\s*Theme\.fontSans/,
        "the toast style must stay on the general UI face");
    assert.match(centre, /face:\s*Theme\.fontMenu/,
        "the centre style must follow the menu font");
    // The centre is a popover, so every size it names must be a Theme token —
    // the 12px floor is enforced there and nowhere else.
    assert.doesNotMatch(centre.replace(/^\s*(bodyLines|bodyLeading|trailingHeight):.*$/gm, ""),
        /:\s*\d+(?:\.\d+)?\s*,?$/m,
        "the centre style names a raw text size instead of a Theme token");
});

test("the toast countdown stays inside the rounded notification card", () => {
    const toast = read("NotificationToasts.qml");

    assert.match(toast, /height:\s*contentHeight\s*\n/,
        "the countdown belongs in the card padding, not in extra space below its content");
    assert.match(toast, /anchors\.leftMargin:\s*card\.padH/);
    assert.match(toast, /anchors\.rightMargin:\s*card\.padH/);
    assert.match(toast, /anchors\.bottomMargin:\s*card\.padV\s*\/\s*2/,
        "the countdown must be inset from the card's curved bottom edge");
    assert.doesNotMatch(toast, /anchors\.margins:\s*1/,
        "a nearly edge-to-edge bar escapes the rounded card silhouette");
});

function keysSuppliedSource(rel) {
    const source = read(rel);
    const start = source.indexOf("readonly property var cardStyle: ({");
    const end = source.indexOf("})", start);
    assert.ok(start !== -1 && end !== -1, `${rel} must declare a cardStyle object`);
    return source.slice(start, end);
}
