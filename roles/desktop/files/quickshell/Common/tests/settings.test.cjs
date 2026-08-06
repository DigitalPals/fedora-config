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

test("regression fixes keep asynchronous state identity-safe", () => {
    const wallpaper = read("Common/Wallpaper.qml");
    const sysInfo = read("Common/SysInfo.qml");
    const bar = read("Bar/Bar.qml");
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
