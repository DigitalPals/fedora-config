const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const shellDir = path.resolve(__dirname, "../..");

function read(relative) {
    return fs.readFileSync(path.join(shellDir, relative), "utf8");
}

test("every Settings/*.qml type is listed in Settings/qmldir", () => {
    // Sibling-type resolution in Settings/ depends on the explicit qmldir
    // index; a file missing from it fails at runtime as "X is not a type".
    const qmldir = read("Settings/qmldir");
    const files = fs.readdirSync(path.join(shellDir, "Settings"))
        .filter(name => name.endsWith(".qml"));
    assert.ok(files.length > 0);
    for (const file of files) {
        const type = file.replace(/\.qml$/, "");
        assert.match(qmldir, new RegExp(`^${type} ${file}$`, "m"),
            `Settings/qmldir must list ${file}`);
    }
});

test("the settings IPC target is declared exactly once shell-wide", () => {
    const qmlFiles = [];
    const walk = dir => {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            if (entry.isDirectory() && !entry.name.startsWith(".") && entry.name !== "tests")
                walk(path.join(dir, entry.name));
            else if (entry.name.endsWith(".qml"))
                qmlFiles.push(path.join(dir, entry.name));
        }
    };
    walk(shellDir);
    const declaring = qmlFiles.filter(file =>
        /target:\s*"settings"/.test(fs.readFileSync(file, "utf8")));
    assert.deepEqual(declaring.map(file => path.relative(shellDir, file)),
        ["shell.qml"]);
});

test("settings is a connected center popout rather than a modal window", () => {
    const shell = read("shell.qml");
    const popouts = read("Common/Popouts.qml");
    const host = read("Bar/IslandPopout.qml");
    const settings = read("Common/Settings.qml");

    assert.equal(fs.existsSync(path.join(shellDir, "SettingsWindow.qml")), false);
    assert.doesNotMatch(shell, /SettingsWindow\s*\{/);
    assert.match(popouts, /settings:\s*"center"/);
    assert.match(host, /settings:\s*"\.\.\/Settings\/SettingsView\.qml"/);
    assert.match(settings,
        /Popouts\.openPanel\("settings",\s*"center",\s*Qt\.rect\(0,\s*0,\s*0,\s*0\)\)/);
});

test("settings exposes responsive output and keyboard contracts", () => {
    const view = read("Settings/SettingsView.qml");
    const host = read("Bar/IslandPopout.qml");
    const modules = read("Settings/ModulesPage.qml");
    const picker = read("Settings/PickerRow.qml");

    assert.match(view, /property real availableWidth/);
    assert.match(view, /property real availableHeight/);
    assert.match(view, /availableWidth\s*<\s*680/);
    assert.match(view, /function handleEscape\(\): bool/);
    assert.match(host, /item\.availableWidth !== undefined/);
    assert.match(host, /item\.availableHeight !== undefined/);
    assert.match(host, /fillBody:\s*host\.slotAName === "settings"/);
    assert.match(host, /width:\s*fillBody \? parent\.width : implicitWidth/);
    assert.match(host, /nameFor\(frontSlot\) !== Popouts\.currentName/,
        "an outgoing popover must not overwrite Settings geometry during a morph");
    assert.match(modules, /Qt\.Key_Space/);
    assert.match(modules, /Qt\.Key_Escape/);
    assert.match(picker, /readonly property real captionWidth/);
    assert.doesNotMatch(picker, /width:\s*root\.narrow \? parent\.width : implicitWidth/,
        "picker flows need a concrete lane width or every pill wraps");
});

test("Idle inhibit and Control Center use the reorderable module pipeline", () => {
    const helpers = read("Common/SettingsHelpers.js");
    const modules = read("Settings/ModulesPage.qml");
    const bar = read("Bar/Bar.qml");

    assert.match(helpers, /"idle", "control"/);
    assert.match(modules, /idle:\s*\{ name: "Idle inhibit"/);
    assert.match(modules, /control:\s*\{ name: "Control Center"/);
    assert.doesNotMatch(modules, /pinnedTail|text:\s*"pinned"/);
    assert.match(bar, /idle:\s*cmpIdle, control:\s*cmpControl/);
    assert.match(bar, /registerPanel\("control", controlIcon\)/);
    assert.doesNotMatch(bar, /togglePopout\("control", "right"/);
});

test("an open Settings panel preserves menubar hover switching", () => {
    const bar = read("Bar/Bar.qml");
    const icon = read("Bar/BarIcon.qml");
    const t3 = read("Bar/T3Chip.qml");
    const usage = read("Bar/UsageChips.qml");
    const hoverOpen = bar.match(/function hoverOpen\([\s\S]*?\n    \}/)?.[0] ?? "";

    assert.match(hoverOpen, /!Popouts\.open \|\| Popouts\.currentName === name/);
    assert.match(hoverOpen, /pendingHoverName === name/,
        "pointer motion must not keep restarting the hover-switch delay");
    assert.doesNotMatch(hoverOpen, /currentName === "settings"/,
        "Settings must not disarm the click-once, hover-between-modules interaction");
    assert.match(bar, /onPointChanged:\s*barWindow\.hoverPanelAt\(point\.position\)/,
        "the full-bar handler must route hover motion around stale MouseArea enter state");
    assert.match(bar, /function hoverPanelAt\(position\)[\s\S]*Object\.keys\(panelAnchors\)/);
    for (const source of [bar, icon, t3, usage])
        assert.match(source, /onPositionChanged:[^\n]*(hoverOpen|entered|chipEntered)/,
            "module hover must recover when a mapped popout costs Qt an enter event");
});

test("regression fixes keep asynchronous state identity-safe", () => {
    const wallpaper = read("Common/Wallpaper.qml");
    const sysInfo = read("Common/SysInfo.qml");
    const bar = read("Bar/Bar.qml");
    const tooltip = read("Bar/BarTooltip.qml");
    const packages = fs.readFileSync(path.resolve(shellDir, "../../tasks/main.yml"), "utf8");

    assert.match(wallpaper, /property string activeAccentFor/);
    assert.match(wallpaper, /Settings\.wall === completedFor/);
    assert.match(wallpaper, /Settings\.set\("wallAccentFor", completedFor\)/);
    assert.match(wallpaper, /property bool accentBusy/);
    assert.match(wallpaper, /property string accentError/);
    assert.match(packages, /- ImageMagick/);
    assert.match(sysInfo, /property string nightLightLifecycle/);
    assert.doesNotMatch(sysInfo, /running:\s*root\.nightLight/);
    assert.match(bar, /Component\.onCompleted:[\s\S]*Settings\.autoHide[\s\S]*hideTimer\.restart/);
    assert.match(tooltip,
        /target:\s*Popouts[\s\S]*function onOpenChanged\(\)[\s\S]*delay\.stop\(\)[\s\S]*root\.ready = false/,
        "tooltips must be disarmed when a popout surface maps or unmaps");
});

test("schema and committed defaults remain version one", () => {
    const helpers = read("Common/SettingsHelpers.js");
    assert.match(helpers, /var VERSION = 1/);
    assert.match(helpers, /warmth:\s*3400/);
    assert.match(helpers, /osd:\s*"top"/);
    assert.match(helpers, /media", on: false/);
    assert.match(helpers, /bt", on: false/);
});

test("the settings store keeps its fixed literal state path", () => {
    const settings = read("Common/Settings.qml");
    assert.match(settings,
        /Quickshell\.env\("HOME"\) \+ "\/\.local\/state\/quickshell\/shell-settings\.json"/);
    assert.match(settings, /path:\s*root\.filePath/);
    assert.doesNotMatch(settings, /:\s*Quickshell\.statePath\(/,
        "Settings must not use statePath — it forks per config directory");
});
