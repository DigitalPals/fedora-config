const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

function read(rel) {
    return fs.readFileSync(path.join(shellDir, rel), "utf8");
}

test("expressive text and reveal motion use the shared timing language", () => {
    const text = read("Common/AnimatedText.qml");
    const reveal = read("Common/Revealer.qml");

    assert.match(text, /Behavior on text/);
    assert.match(text, /PropertyAction \{\}/,
        "the outgoing label must leave before the new value is committed");
    assert.match(text, /Theme\.springCurve/);
    assert.match(reveal, /Behavior on implicitHeight/);
    assert.match(reveal, /visible:\s*reveal \|\|/,
        "revealed content must survive its exit transition");

    const actions = read("Common/NotifActions.qml");
    assert.match(actions, /Revealer\s*\{/);
    assert.match(actions, /Notifs\.secondaryActions\(entry\)/);
    assert.doesNotMatch(actions, /items:\s*reveal\s*\?/,
        "notification actions must not vanish before the revealer closes");

    const clock = read("Bar/Modules/Clock.qml");
    assert.match(clock, /AnimatedText\s*\{/);
    assert.match(clock, /animateChange:\s*!Settings\.modOpts\.clock\.seconds/,
        "a seconds clock should not run a transition every second");
});

test("the center cluster keeps clock spacing and restores the weather hairline", () => {
    const divider = read("Bar/Divider.qml");
    const cluster = read("Bar/Cluster.qml");
    const clock = read("Bar/Modules/Clock.qml");

    assert.match(divider, /width:\s*kind === "space" \? 8 : 9/,
        "classic spacing and hairlines must remain compact");
    assert.match(divider, /visible:\s*root\.kind === "rule"/,
        "space separators must not draw a mark");
    assert.match(cluster, /function previousShownId\(at\)/);
    assert.match(cluster, /entry\.modelData\.entry\.id === "clock"/);
    assert.match(cluster, /=== "indicators"\)[\s\S]{0,80}?\? "space" : "rule"/);
    assert.match(clock, /id:\s*dateSeparator[\s\S]{0,60}?kind:\s*"space"/);
    assert.doesNotMatch(divider + cluster + clock, /kind:\s*"dot"/);
});

test("scroll chrome discloses overflow without becoming an input surface", () => {
    const chrome = read("Common/ScrollChrome.qml");
    assert.match(chrome, /required property Flickable target/);
    assert.match(chrome, /target\.atYBeginning/);
    assert.match(chrome, /target\.atYEnd/);
    assert.match(chrome, /visibleArea\.heightRatio/);
    assert.doesNotMatch(chrome, /MouseArea|TapHandler|WheelHandler|DragHandler/);

    for (const rel of [
        "Popovers/GitHubPopover.qml", "Popovers/T3InboxPage.qml",
        "Popovers/T3Picker.qml", "Popovers/T3ThreadPage.qml",
        "Settings/FolderDialog.qml", "Settings/ModulesPage.qml",
        "Settings/SettingsPage.qml"
    ])
        assert.match(read(rel), /ScrollChrome\s*\{/,
            `${rel} does not use the shared viewport treatment`);
});

test("primary loading and empty states use a settled, gated placeholder", () => {
    const placeholder = read("Common/StatusPlaceholder.qml");
    assert.match(placeholder, /running:\s*root\.shown && root\.kind === "loading"/,
        "the progress mark must stop when the status is hidden or settled");
    assert.match(placeholder, /Behavior on implicitHeight/);
    assert.match(placeholder, /Theme\.redBgSoft/);

    for (const rel of [
        "Popovers/GitHubPopover.qml", "Popovers/NotifsPopover.qml",
        "Popovers/T3InboxPage.qml", "Popovers/T3ThreadPage.qml",
        "Settings/WallpaperPage.qml"
    ])
        assert.match(read(rel), /StatusPlaceholder\s*\{/,
            `${rel} still lacks the shared empty/loading treatment`);
});
