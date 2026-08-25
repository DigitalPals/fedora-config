const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

function read(rel) {
    return fs.readFileSync(path.join(shellDir, rel), "utf8");
}

// T3's metrics now defer to the shell's shared panel rhythm rather than
// restating it, so a token may resolve either to a literal or to one hop
// through Theme. Follow that hop rather than banning it: the point of the
// assertion is the resulting number, and pinning the literal here is what
// would let T3 and the menubar drift apart again.
function intToken(source, name, theme) {
    const match = source.match(new RegExp(
        `readonly property int ${name}:\\s*(?:Theme\\.(\\w+)|(\\d+))`));
    assert.ok(match, `${name} must remain an integer token`);
    if (match[2] !== undefined)
        return Number(match[2]);
    assert.ok(theme, `${name} defers to Theme.${match[1]}; pass Theme.qml to resolve it`);
    return intToken(theme, match[1]);
}

test("every T3 thread row is one flat line with room for its hover icons", () => {
    const theme = read("Common/Theme.qml");
    const t3Theme = read("Common/T3Theme.qml");
    const inbox = read("Popovers/T3InboxPage.qml");

    const rowHeight = intToken(t3Theme, "quietRowHeight", theme);

    assert.match(inbox, /height:\s*T3Theme\.quietRowHeight/,
        "the inbox draws one row height; a thread is not a card");
    assert.doesNotMatch(inbox, /T3Theme\.activeRowHeight/,
        "the two-height row is gone — the tall form belongs to GitHub rows now");

    // The pill form is Theme.inlineActionHeight (32) and does not fit the
    // one-menubar-tall row with margin, which is why the row uses its own
    // smaller icon control.
    const controlSize = inbox.match(
        /component RowAction: IconButton \{\s*controlSize:\s*Theme\.(\w+)/);
    assert.ok(controlSize, "expected the row's own icon-button size");
    const control = intToken(theme, controlSize[1]);
    assert.ok(control <= rowHeight - 8,
        "hover icons leave too little margin inside the thread row");
    assert.ok(control < intToken(theme, "inlineActionHeight"),
        "the row control must be denser than the shared inline pill");

    assert.match(inbox,
        /id:\s*actionsScope[\s\S]*?anchors\.verticalCenter:\s*row\.verticalCenter/,
        "hover actions must be centered against the full thread row");
});

test("the thread row paints no neutral card and no redundant Open pill", () => {
    const inbox = read("Popovers/T3InboxPage.qml");
    const row = inbox.match(/Rectangle \{\s*id:\s*row\b([\s\S]*?)\n {12}\}/);

    assert.ok(row, "expected the thread row rectangle");
    assert.doesNotMatch(row[1], /T3Theme\.surface/,
        "an active thread must not sit on a grey card");
    assert.match(row[1],
        /color:\s*entry\.flagged \?[\s\S]*?T3Theme\.amberSoft\) : "transparent"/,
        "only attention and error rows carry a fill");
    assert.match(row[1], /border\.width:\s*activeFocus \|\| entry\.flagged \? 1 : 0/,
        "the hairline card border goes with the card");

    assert.doesNotMatch(inbox, /label:\s*"Open"/,
        "opening is what the row itself does; the pill only repeated it");
    assert.match(inbox, /id:\s*meta\b[\s\S]*?entry\.thread\.project/,
        "the project moved onto the title line rather than being dropped");
});
