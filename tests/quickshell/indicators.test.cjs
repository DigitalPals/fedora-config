const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

function read(relative) {
    return fs.readFileSync(path.join(shellDir, relative), "utf8");
}

const indicators = read("Bar/Modules/Indicators.qml");

test("indicators declares the six canonical quick actions in order", () => {
    const actionBlock = indicators.match(/readonly property var actions:\s*\[([\s\S]*?)\n\s*\]/)?.[1] ?? "";
    const ids = [...actionBlock.matchAll(/id:\s*"([^"]+)"/g)].map(match => match[1]);
    assert.deepEqual(ids, [
        "dictation", "recording", "reminder", "night-light", "dnd", "stay-awake"
    ]);
});

test("inactive disclosure and persistent active actions use separate animated blocks", () => {
    const cluster = read("Bar/Cluster.qml");
    const revealer = read("Common/Revealer.qml");
    assert.match(indicators, /readonly property var inactiveActions:/);
    assert.match(indicators, /readonly property var activeActions:/);
    assert.match(indicators,
        /Revealer\s*\{[\s\S]{0,180}?orientation:\s*Qt\.Horizontal[\s\S]{0,180}?reveal:\s*root\.revealInactive/);
    assert.match(indicators, /opacity:\s*reveal \? 0\.58 : 0/);
    assert.match(indicators, /activeOrder = current/,
        "already-active actions initialize in canonical order");
    assert.match(indicators, /next\.unshift\(id\)/,
        "new actions enter on the outer side without reordering existing states");
    assert.match(indicators, /Settings\.modOpts\.indicators\.mode === "always"/);
    assert.match(indicators, /interval:\s*180/,
        "leaving the bar should use a short anti-oscillation delay");
    assert.match(indicators, /root\.host\.tooltipPointerInside/,
        "disclosure stays latched while the pointer crosses the rest of the bar");
    assert.match(revealer, /readonly property bool widthAnimating:[\s\S]{0,100}?horizontalWidthAnimation\.running/);
    assert.match(revealer,
        /easing\.bezierCurve:\s*root\.reveal\s*\? Theme\.springCurve : Theme\.easeInCurve/,
        "closing disclosure must not spring past zero width and rebound");
    assert.match(indicators,
        /host\.indicatorDisclosureAnimating = disclosureAnimating/);
    assert.match(cluster,
        /group\.kind === "center"[\s\S]{0,100}?root\.host\.indicatorDisclosureAnimating/,
        "the old center-pill spring must yield while the revealer owns width motion");
    const bar = read("Bar/Bar.qml");
    assert.match(bar,
        /readonly property real centerPinBias:[\s\S]{0,180}?currentCenterExtents\(\)/,
        "the clock pin must follow reveal geometry synchronously");
    assert.doesNotMatch(bar, /centerPinBias\s*=/,
        "the deferred fit pass must not assign the clock pin a frame late");
    assert.match(bar,
        /id:\s*centerCluster[\s\S]*?x:\s*parent\.width \/ 2 - barWindow\.currentClockPin\(\)/,
        "center placement must use the clock pin directly, without cancelling two changing widths");
    assert.match(bar, /function itemCenterXWithin\([\s\S]*?position \+= current\.x/,
        "clock placement must react to each intermediate Row layout position");
});

test("center pointer routing leaves action buttons above the notification target", () => {
    const cluster = read("Bar/Cluster.qml");
    const bar = read("Bar/Bar.qml");
    assert.match(cluster, /id:\s*slotRow\s*\n\s*z:\s*2/);
    assert.match(cluster, /id:\s*groupMouse\s*\n\s*z:\s*1/);
    assert.match(cluster, /!root\.host\.indicatorActionHovered/,
        "the center tooltip must disappear over a real action");
    assert.match(bar, /actionAtScenePoint\(scenePoint\)/,
        "the bar-wide pointer path must independently hit-test action buttons");
    assert.match(indicators, /acceptedButtons:\s*Qt\.LeftButton \| Qt\.MiddleButton/);
});

test("recording and dictation expose their complete live state", () => {
    assert.match(indicators, /Recorder\.elapsedLabel/);
    assert.match(indicators, /running:\s*button\.recording[\s\S]{0,100}?Animation\.Infinite/,
        "recording must pulse while its elapsed timer is shown");
    assert.match(indicators, /Dictation\.recording/);
    assert.match(indicators, /Dictation\.transcribing/);
    assert.match(indicators, /"progress_activity"/);
    assert.match(indicators, /RotationAnimation on rotation/);
    assert.match(indicators, /mouseButton === Qt\.MiddleButton \? "nl" : "en"/);

    const clock = read("Bar/Modules/Clock.qml");
    const bar = read("Bar/Bar.qml");
    assert.doesNotMatch(clock, /StateMark|do_not_disturb_on|coffee/);
    assert.doesNotMatch(bar, /RecordingChip\s*\{/);
    assert.equal(fs.existsSync(path.join(shellDir, "Bar/RecordingChip.qml")), false);
});

test("all shared toggles use one persisted write path", () => {
    const sys = read("Common/SysInfo.qml");
    const control = read("Popovers/ControlCenterPopover.qml");
    assert.match(sys, /readonly property bool nightLight:\s*Settings\.nightLight/);
    assert.match(sys, /readonly property bool idleInhibited:\s*Settings\.idleInhibited/);
    assert.match(sys, /function setNightLight\(value\)/);
    assert.match(sys, /function toggleNightLight\(\)/);
    assert.match(sys, /function setIdleInhibited\(value\)/);
    assert.match(sys, /function toggleIdleInhibited\(\)/);
    assert.match(control, /onToggled:\s*SysInfo\.toggleNightLight\(\)/);
    assert.match(control, /onToggled:\s*SysInfo\.toggleIdleInhibited\(\)/);
});

test("reminder manager and shell-wide refresh IPC are wired to the action", () => {
    const registry = read("Common/PanelRegistryData.js");
    const shell = read("shell.qml");
    const manager = read("Popovers/ReminderPopover.qml");
    assert.match(indicators, /panelName:\s*"reminders"/);
    assert.match(registry,
        /name:\s*"reminders"[^\n]+moduleId:\s*"indicators"[^\n]+ReminderPopover\.qml/);
    assert.match(shell, /target:\s*"reminders"[\s\S]{0,120}?Reminders\.refresh\(\)/);
    for (const minutes of [5, 15, 30, 60])
        assert.match(manager, new RegExp(`\\b${minutes}\\b`));
    assert.match(manager, /validator:\s*IntValidator \{ bottom: 1 \}/);
    assert.match(manager, /Optional message/);
    assert.match(manager, /root\.clearArmed \? "Confirm clear all" : "Clear all"/);
    assert.match(manager, /Reminders\.cancel\(reminderRow\.modelData\.id\)/);
});
