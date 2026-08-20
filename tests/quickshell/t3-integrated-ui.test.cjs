const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

function read(rel) {
    return fs.readFileSync(path.join(shellDir, rel), "utf8");
}

const files = [
    "T3CodePopover.qml", "T3InboxPage.qml", "T3ThreadPage.qml",
    "T3Composer.qml", "T3RequestCard.qml", "T3Picker.qml",
    "T3NewThreadPage.qml"
];

test("T3 owns a stable product canvas instead of inheriting wallpaper glass", () => {
    const theme = read("Common/T3Theme.qml");
    const popover = read("Popovers/T3CodePopover.qml");
    const panel = read("Popovers/PopoutPanel.qml");
    const host = read("Bar/PopoutHost.qml");

    assert.match(theme, /readonly property color canvas:\s*dark \? "#0a0a0a" : "#fcfcfc"/);
    assert.match(theme, /readonly property color surface:\s*dark \? "#111111" : "#ffffff"/);
    assert.match(theme, /readonly property color accent:\s*dark \? "#346bf1" : "#1b4ed8"/);
    assert.match(popover, /surfaceColor:\s*T3Theme\.canvas/);
    assert.match(popover, /readonly property int pageMaxWidth:\s*page === "inbox" \? 460 : 520/);
    assert.match(popover, /T3Theme\.dark[\s\S]*?"t3-dark\.svg"/,
        "the wordmark needs a dark asset on the light T3 canvas");
    assert.match(panel, /property color surfaceColor:\s*Theme\.surfaceStrong/);
    assert.match(host, /host\.activePanel\.surfaceColor/);
});

test("T3 navigation uses one contextual header and hides relay detail in overflow", () => {
    const popover = read("Popovers/T3CodePopover.qml");
    const footer = popover.match(/Item\s*\{\s*id:\s*footer\b([\s\S]*?)\n\s*Connections\s*\{/);

    assert.match(popover, /id:\s*inboxHeader[\s\S]*?visible:\s*root\.page === "inbox"/);
    assert.match(popover, /symbol:\s*"edit_square"/);
    assert.match(popover, /id:\s*connectionMenu/);
    assert.match(popover, /T3Code\.host\.replace/);
    assert.ok(footer, "expected the compact connection footer");
    assert.doesNotMatch(footer[1], /T3Code\.host/,
        "the raw relay host belongs in overflow, not permanent footer chrome");
});

test("the T3 composer is one rounded glass shell with inline controls", () => {
    const composer = read("Popovers/T3Composer.qml");
    const theme = read("Common/T3Theme.qml");

    assert.match(composer, /id:\s*composerShell[\s\S]*?radius:\s*T3Theme\.composerRadius/);
    assert.match(theme, /readonly property int composerRadius:\s*22/);
});

test("the T3 composer exposes an attached settings drawer and round send action", () => {
    const composer = read("Popovers/T3Composer.qml");
    const send = composer.match(/Rectangle\s*\{\s*id:\s*sendButton\b([\s\S]*?)\n\s*Sym\s*\{/);

    assert.match(composer, /id:\s*settingsDrawer[\s\S]*?visible:\s*settingsPresentation\.expanded/);
    assert.match(composer, /text:\s*"Ask anything…"/);
    assert.ok(send, "expected the composer's Material Symbol send button");
    assert.match(send[1], /width:\s*Theme\.inlineActionHeight/);
    assert.match(send[1], /height:\s*Theme\.inlineActionHeight/);
    assert.match(send[1], /radius:\s*width \/ 2/);
    assert.match(composer, /name:\s*root\.sending \? "more_horiz" : "arrow_upward"/);
    assert.doesNotMatch(composer, /Enter to send · Ctrl\+Enter/,
        "keyboard help must not be permanent visual chrome");
});

test("thread transcript follows T3 message rhythm and attaches response UI", () => {
    const thread = read("Popovers/T3ThreadPage.qml");
    const message = thread.match(/component MessageCard:\s*Item\s*\{([\s\S]*?)\n\s*component MenuEntry:/);

    assert.ok(message, "expected the transcript message component");
    assert.match(message[1], /fromUser \? width \* 0\.82 : width/);
    assert.match(message[1], /x:\s*parent\.width - messageCard\.messageWidth/);
    assert.match(message[1], /textFormat:\s*messageCard\.fromUser \? Text\.PlainText : Text\.MarkdownText/);
    assert.match(message[1], /messageHover\.hovered \|\| activeFocus/);
    assert.doesNotMatch(message[1], /text:\s*messageCard\.fromUser \? "You"/,
        "permanent role labels should not interrupt the transcript");

    const attachments = thread.indexOf("id: composerAttachmentsViewport");
    const composer = thread.lastIndexOf("id: composer");
    const timeline = thread.indexOf("id: timeline");
    const request = thread.indexOf("T3RequestCard {", timeline);
    assert.ok(attachments > timeline && attachments < composer);
    assert.ok(request >= attachments && request < composer,
        "requests must be attached above the composer rather than embedded in the timeline");
});

test("composer-attached questions keep numbered options keyboard actionable", () => {
    const request = read("Popovers/T3RequestCard.qml");

    assert.match(request, /required property int index/);
    assert.match(request, /option\.index < 9 \? String\(option\.index \+ 1\)/);
    assert.match(request, /event\.key >= Qt\.Key_1 && event\.key <= Qt\.Key_9/);
});

test("inbox uses full active cards, compact parked rows, search, and inline state", () => {
    const inbox = read("Popovers/T3InboxPage.qml");

    assert.match(inbox, /id:\s*searchBox/);
    assert.match(inbox, /entry\.compact \? T3Theme\.quietRowHeight : T3Theme\.activeRowHeight/);
    assert.match(inbox, /entry\.compact \? "transparent" : T3Theme\.surface/);
    assert.match(inbox, /name:\s*entry\.statusSymbol/);
    assert.doesNotMatch(inbox, /id:\s*rail\b/);
    assert.doesNotMatch(inbox, /Animation\.Infinite/,
        "thread state must not repaint the popout continuously");
});

test("all T3 views use the product typeface and Material Symbol controls", () => {
    const combined = files.map(file => read(`Popovers/${file}`)).join("\n");

    assert.doesNotMatch(combined, /Theme\.fontMenu|font\.family:\s*Theme\.fontMono/);
    assert.doesNotMatch(combined,
        /(?<!T3)Theme\.(?:surfaceStrong|surfaceMenu|insetSurface|textHi|textMid|textLow|textDim|textFaint|accentBg|accentFg|hoverFill|cardFill|hairlineSoft)/,
        "T3 views must not leak wallpaper-derived shell colors into the product canvas");
    assert.doesNotMatch(combined, /[←↗↻⋯▴▾▸]/,
        "typographic control glyphs must use the shared symbol component");
    assert.match(combined, /Sym\s*\{/);
});
