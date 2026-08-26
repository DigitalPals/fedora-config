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
    const bar = read("Bar/Bar.qml");
    assert.match(cluster,
        /groupHovered:\s*entry\.modelData\.entry\.id === "indicators"[\s\S]{0,100}?indicatorTriggerHovered/,
        "the separate clock pill must still disclose its neighbouring actions");
    assert.match(cluster,
        /group\.items\[0\]\.entry\.id === "indicators"[\s\S]{0,100}?indicatorDisclosureAnimating/,
        "the Indicators wrapper must yield while its revealer owns width motion");
    assert.match(bar,
        /indicatorTriggerHovered = barWindow\.itemContainsPoint\([\s\S]{0,100}?panelAnchors\.calendar/,
        "bar-wide pointer truth must recover a clock enter lost while mapping a popout");
    assert.doesNotMatch(cluster, /kind === "center"|center:\s*"notifications"/,
        "the indicators must not depend on a shared notification-center target");
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

test("clock and weather own their targets without covering indicator actions", () => {
    const cluster = read("Bar/Cluster.qml");
    const clock = read("Bar/Modules/Clock.qml");
    const weather = read("Bar/Modules/Weather.qml");
    assert.match(clock, /BarChip\s*\{[\s\S]*?panelName:\s*"calendar"/);
    assert.match(weather, /BarChip\s*\{[\s\S]*?panelName:\s*"weather"/);
    assert.match(cluster, /ownsPointer:\s*kind === "status"/);
    assert.doesNotMatch(cluster, /center:\s*"notifications"/);
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

test("active clock-side actions light only their glyph", () => {
    const action = indicators.slice(
        indicators.indexOf("component IndicatorAction:"),
        indicators.indexOf("Revealer {"));

    assert.match(action, /activeState \? Theme\.barAccent\b/);
    assert.doesNotMatch(action, /activeState \? Theme\.barAccentFg\b/);
    assert.match(action, /color:\s*recording \? Theme\.barRed : "transparent"/,
        "an active toggle must not paint an accent pill behind its glyph");
    assert.match(action,
        /BarHover\s*\{[\s\S]{0,120}?target:\s*button/,
        "clock-side actions must use the same hover surface as other modules");
    assert.doesNotMatch(action,
        /\n\s*color:\s*[\s\S]{0,100}?activeState/);
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

test("large Control Center states use subdued accent containers", () => {
    const theme = read("Common/Theme.qml");
    const control = read("Popovers/ControlCenterPopover.qml");
    const slider = read("Popovers/FillSlider.qml");
    const radioRow = control.slice(
        control.indexOf("component RadioRow:"),
        control.indexOf("component QuickTile:"));

    assert.match(theme,
        /readonly property color accentContainer:\s*SettingsHelpers\.mixHex\([\s\S]{0,120}?dark \? 0\.46 : 0\.30\)/);
    assert.match(theme,
        /readonly property color accentContainerFg:\s*SettingsHelpers\.foregroundFor/);
    // The radios are rows: they carry a value and a chevron, and a row that is
    // merely connected is not a selection, so nothing about them is painted.
    // Only its mark takes the accent.
    assert.match(radioRow, /color: radioMouse\.containsMouse \? Theme\.chip : "transparent"/);
    assert.doesNotMatch(radioRow, /Theme\.(?:accentContainer|accentSoft|accentBg|accentSubtle)/,
        "a radio row must not paint an accent field behind its label");
    assert.match(radioRow, /color: radio\.on \? Theme\.accent : Theme\.icon/,
        "the accent survives on the glyph, where it is a mark");

    // A quick action and a switch track are the same idea, so they light the
    // same way — on the subdued container, never on full accent. The ban is
    // scoped to the tile's own fill: full accent on a 20px *glyph* is a mark,
    // which is exactly where the accent is supposed to survive.
    const quickTile = control.slice(
        control.indexOf("component QuickTile:"),
        control.indexOf("component StatColumn:"));
    assert.match(quickTile, /tile\.on \? Theme\.accentContainer/);
    assert.doesNotMatch(quickTile, /tile\.on \? Theme\.accent\b/);
    // A running capture is the one state that owns a field of its own, and it
    // is the error colour, not the accent.
    assert.match(quickTile, /tile\.alert \? Theme\.redBg/);
    assert.doesNotMatch(control, /current \? Theme\.accent\b/,
        "the power profile is a segmented control; it lights the held chip");
    assert.match(control, /current \? Theme\.chipHover/);
    assert.match(slider,
        /GradientStop \{ position: 1; color: Theme\.accentSoft \}/);
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
