const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname,
    "../../roles/desktop/files/quickshell/Popovers");
const source = name => fs.readFileSync(path.join(root, name), "utf8");

test("integration popovers offer bounded, keyboard-collapsible workspaces", () => {
    for (const [name, compact] of [
        ["T3CodePopover.qml", 460],
        ["GitHubPopover.qml", 460],
        ["HermesPopover.qml", 520]
    ]) {
        const qml = source(name);
        assert.match(qml, /property bool workspaceExpanded:\s*false/,
            `${name} must open in its glanceable mode`);
        assert.match(qml, new RegExp(`workspaceExpanded \\? 760[\\s\\S]{0,100}?${compact}`),
            `${name} must expose the common expanded width`);
        assert.match(qml, /Math\.min\([\s\S]{0,100}?root\.availableWidth\)/,
            `${name} must remain bounded by the output`);
        assert.match(qml, /function handleEscape\(\): bool[\s\S]*?workspaceExpanded[\s\S]*?= false/,
            `${name} must let Escape leave expanded mode`);
        assert.match(qml, /symbol:\s*root\.workspaceExpanded\s*\? "close_fullscreen" : "open_in_full"/);
        assert.match(qml, /accessibleName:\s*root\.workspaceExpanded/);
    }
});

test("Hermes exposes the same workspace action on conversations and setup", () => {
    const popover = source("HermesPopover.qml");
    const inbox = source("HermesInboxPage.qml");
    assert.match(popover, /workspaceExpanded:\s*root\.workspaceExpanded/);
    assert.match(popover,
        /onWorkspaceToggleRequested:\s*root\.workspaceExpanded = !root\.workspaceExpanded/);
    assert.match(inbox, /signal workspaceToggleRequested\(\)/);
    assert.match(inbox, /onTriggered:\s*root\.workspaceToggleRequested\(\)/);
});
