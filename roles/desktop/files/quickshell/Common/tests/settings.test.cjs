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
        ["SettingsWindow.qml"]);
});

test("the settings store keeps its fixed literal state path", () => {
    const settings = read("Common/Settings.qml");
    assert.match(settings,
        /Quickshell\.env\("HOME"\) \+ "\/\.local\/state\/quickshell\/shell-settings\.json"/);
    assert.match(settings, /path:\s*root\.filePath/);
    assert.doesNotMatch(settings, /:\s*Quickshell\.statePath\(/,
        "Settings must not use statePath — it forks per config directory");
});
