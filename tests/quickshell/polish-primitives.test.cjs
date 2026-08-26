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

test("clock and weather use separate transparent-resting pills", () => {
    const divider = read("Bar/Divider.qml");
    const cluster = read("Bar/Cluster.qml");
    const clock = read("Bar/Modules/Clock.qml");
    const weather = read("Bar/Modules/Weather.qml");
    const helpers = read("Common/SettingsHelpers.js");

    assert.match(divider, /width:\s*kind === "space" \? 8 : 9/,
        "classic spacing and hairlines must remain compact");
    assert.match(divider, /visible:\s*root\.kind === "rule"/,
        "space separators must not draw a mark");
    assert.match(clock, /BarChip\s*\{[\s\S]*?panelName:\s*"calendar"/);
    assert.match(weather, /BarChip\s*\{[\s\S]*?panelName:\s*"weather"/);
    assert.match(clock, /id:\s*dateSeparator[\s\S]{0,60}?kind:\s*"space"/);
    assert.match(helpers,
        /indicators:\s*"solo", clock:\s*"solo", weather:\s*"solo"/);
    assert.doesNotMatch(cluster, /kind === "center"|center:\s*"notifications"/);
    assert.doesNotMatch(divider + cluster + clock + weather, /kind:\s*"dot"/);
});

test("menubar modules rest directly on one shared slab", () => {
    const chip = read("Bar/BarChip.qml");
    const icon = read("Bar/BarIcon.qml");
    const t3 = read("Bar/T3Chip.qml");
    const usage = read("Bar/UsageChips.qml");
    const tray = read("Bar/Modules/Tray.qml");
    const media = read("Bar/Modules/Media.qml");
    const workspaces = read("Bar/Workspaces.qml");

    assert.match(chip, /property color restFill:\s*"transparent"/);
    assert.match(icon, /property color restFill:\s*"transparent"/);
    assert.match(t3, /restFill:\s*"transparent"/);
    assert.match(usage,
        /color:\s*root\.held \? Theme\.barChipHover : "transparent"/);
    assert.match(usage,
        /current \? Theme\.barChipHover[\s\S]{0,40}?: "transparent"/);
    assert.match(tray, /id:\s*pill[\s\S]{0,180}?color:\s*"transparent"/);
    assert.doesNotMatch(media, /color:\s*Theme\.barChipHover/,
        "the media glyph must not retain a private resting disc");
    assert.match(workspaces, /id:\s*activeLozenge[\s\S]{0,700}?color:\s*Theme\.barWsCurrent/,
        "the current workspace remains the deliberate background exception");
});

test("every module family uses the shared bar hover surface", () => {
    const hover = read("Bar/BarHover.qml");
    const chip = read("Bar/BarChip.qml");
    const icon = read("Bar/BarIcon.qml");
    const bar = read("Bar/Bar.qml");
    const cluster = read("Bar/Cluster.qml");
    const tray = read("Bar/Modules/Tray.qml");
    const usage = read("Bar/UsageChips.qml");
    const indicators = read("Bar/Modules/Indicators.qml");
    const clock = read("Bar/Modules/Clock.qml");
    const weather = read("Bar/Modules/Weather.qml");
    const workspaces = read("Bar/Workspaces.qml");

    assert.match(hover, /^import[\s\S]*StateLayer\s*\{/,
        "the bar hover primitive must retain the shared Material state layer");
    assert.match(hover, /required property Bar host/);
    assert.match(hover, /required property Item target/);
    assert.match(hover, /hovered:\s*visualEnabled && over/);
    assert.match(hover,
        /PointerCheck\s*\{[\s\S]{0,180}?target:\s*root\.target[\s\S]{0,220}?hovered:\s*true/,
        "hover visuals must use the bar-wide scene point, not a child MouseArea");
    assert.match(hover, /readonly property PointerCheck check:\s*pointer/,
        "the visual background and tooltip must share one pointer answer");

    for (const [name, source] of [["content chip", chip], ["icon", icon]]) {
        assert.match(source,
            /BarHover\s*\{[\s\S]{0,140}?host:\s*root\.host[\s\S]{0,80}?target:\s*root/,
            `${name} does not use the shared bar hover primitive`);
        assert.match(source, /readonly property bool hovered:\s*hover\.over/);
        assert.match(source, /BarTooltip\s*\{[\s\S]{0,80}?check:\s*hover\.check/);
    }

    assert.match(bar, /HoverHandler\s*\{[\s\S]{0,180}?blocking:\s*false/,
        "the bar-wide pointer observer must not take a module click");
    assert.match(cluster,
        /BarHover\s*\{[\s\S]{0,180}?visible:\s*group\.ownsPointer[\s\S]{0,100}?target:\s*pill/,
        "the combined status click target needs one matching hover surface");
    assert.match(cluster, /ownsPointer:\s*kind === "status"/);
    assert.match(cluster, /groupHovered:[\s\S]{0,120}?indicatorTriggerHovered/);
    assert.match(clock, /BarChip\s*\{/);
    assert.match(weather, /BarChip\s*\{/);
    assert.doesNotMatch(cluster, /sharedHoverLayer|slotLoader\.mod,[\s\S]{0,80}?tooltipPointerPosition/,
        "status content must not grow independent affordances beneath one click target");

    for (const [name, source] of [
        ["tray", tray], ["usage", usage], ["indicators", indicators],
        ["workspaces", workspaces]
    ])
        assert.match(source, /BarHover\s*\{/,
            `${name} bypasses the shared hover surface`);
});

test("resting menubar icons share one tone while weather keeps its palette", () => {
    const bar = read("Bar/Bar.qml");
    const updates = read("Bar/Modules/Updates.qml");
    const media = read("Bar/Modules/Media.qml");
    const tray = read("Bar/Modules/Tray.qml");
    const volume = read("Bar/Modules/Volume.qml");
    const wifi = read("Bar/Modules/Wifi.qml");
    const bluetooth = read("Bar/Modules/Bluetooth.qml");
    const battery = read("Bar/Modules/Battery.qml");
    const github = read("Bar/Modules/GitHub.qml");
    const t3 = read("Bar/T3Chip.qml");
    const usage = read("Bar/UsageChips.qml");
    const weather = read("Bar/Modules/Weather.qml");

    assert.equal((bar.match(/idleColor:\s*Theme\.barIcon/g) || []).length, 2,
        "launcher and power must use the shared resting icon tone");
    assert.match(updates, /idleColor:\s*Theme\.barIcon/);
    assert.match(media, /name:\s*root\.playing[\s\S]{0,180}?color:\s*Theme\.barIcon/);
    assert.match(tray, /Theme\.barTextHi : Theme\.barIcon/);
    assert.match(volume, /Audio\.muted \? Theme\.barRedText : Theme\.barIcon/);
    assert.match(wifi, /color:\s*Theme\.barIcon/);
    assert.match(bluetooth, /color:\s*Theme\.barIcon/);
    assert.match(battery, /Battery\.pluggedIn \? Theme\.barAccent : Theme\.barIcon/);
    assert.match(github, /Theme\.barTextHi : Theme\.barIcon/);
    assert.match(t3, /opacity:\s*root\.live \? 1 : 0\.52/);
    assert.match(t3, /colorizationColor:\s*Theme\.barIcon/);
    assert.match(usage, /opacity:\s*chip\.status === "error" \? 0\.52 : 1/);
    assert.match(usage, /colorizationColor:\s*Theme\.barIcon/);
    assert.match(weather, /color:\s*Weather\.barGlyphColor\(Weather\.code, Weather\.isDay\)/);
    assert.doesNotMatch(weather, /color:\s*Theme\.barIcon/,
        "weather is the intentional coloured-glyph exception");
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
