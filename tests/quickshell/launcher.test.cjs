const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

function read(rel) {
    return fs.readFileSync(path.join(shellDir, rel), "utf8");
}

test("the launcher is warm before the first shortcut press", () => {
    const window = read("LauncherWindow.qml");

    assert.match(window, /LauncherView\s*\{/);
    assert.match(window, /width:\s*launcherView\.implicitWidth/);
    assert.match(window, /height:\s*launcherView\.implicitHeight/);
    assert.doesNotMatch(window, /\bLoader\s*\{|launcherLoader/,
        "constructing LauncherView on demand adds cold-start latency");
});

test("opening claims focus immediately and preserves the first typed key", () => {
    const window = read("LauncherWindow.qml");
    const view = read("LauncherView.qml");

    assert.match(window,
        /keyboardFocus:\s*Launcher\.open\s*\?\s*WlrKeyboardFocus\.Exclusive/);
    assert.match(window, /focus:\s*Launcher\.open/);
    assert.match(window, /!launcherView\.inputActiveFocus/);
    assert.match(window, /launcherView\.handleEarlyKey\(event\)/);

    assert.match(view, /function prepareOpen\(\): void/);
    assert.match(view, /search\.text = "";\s*selected = 0;\s*focusInput\(\);/s);
    assert.match(view, /Qt\.callLater\(\(\) => \{\s*if \(Launcher\.open\)\s*root\.focusInput\(\);/s);
    assert.match(view, /function handleEarlyKey\(event\): bool/);
    assert.match(view, /search\.insert\(search\.cursorPosition, event\.text\)/);
    assert.match(view, /focus:\s*Launcher\.open/);
});

test("Enter activates the selected first result without waiting for animation", () => {
    const view = read("LauncherView.qml");

    assert.match(view, /property int selected:\s*0/);
    assert.match(view,
        /event\.key === Qt\.Key_Return \|\| event\.key === Qt\.Key_Enter\) \{\s*activate\(rows\[selected\]\);/s);
    assert.doesNotMatch(view, /\bentered\b|enterTimer|enterDelay|PauseAnimation/,
        "result-row staging must not make the selected app look unavailable");
});

test("the empty app directory is alphabetical", () => {
    const view = read("LauncherView.qml");
    const emptyReturn = view.indexOf('if (q === "")\n            return 1;');
    const usageBoost = view.indexOf("Launcher.usageBoost(app)");

    assert.ok(emptyReturn >= 0, "an empty query must give every app the same score");
    assert.ok(usageBoost > emptyReturn,
        "launch history may only influence results after the empty-query return");
    assert.match(view,
        /\.sort\(\(a, b\) => b\.score - a\.score \|\| a\.app\.name\.localeCompare\(b\.app\.name\)\)/);
});

test("Super+Space uses Hyprland's in-process global shortcut", () => {
    const shell = read("shell.qml");
    const bindings = fs.readFileSync(path.resolve(shellDir, "../bindings.lua"), "utf8");

    assert.match(shell, /GlobalShortcut\s*\{/);
    assert.match(shell, /appid:\s*"quickshell"/);
    assert.match(shell, /name:\s*"launcherToggle"/);
    assert.match(shell, /onPressed:\s*Launcher\.toggle\(\)/);
    assert.match(bindings,
        /mainMod \.\. " \+ SPACE", hl\.dsp\.global\("quickshell:launcherToggle"\)/);
    assert.doesNotMatch(bindings, /qs ipc call launcher toggle/);
});

test("launcher-only motion stays brief and cannot gate input", () => {
    const theme = read("Common/Theme.qml");
    const window = read("LauncherWindow.qml");

    for (const [token, value] of Object.entries({
        launcherOpenDuration: 180,
        launcherCloseDuration: 120,
        launcherFadeInDuration: 110,
        launcherFadeOutDuration: 80,
        launcherResizeDuration: 140,
        launcherTravel: 8
    })) {
        assert.match(theme, new RegExp(`property (?:int|real) ${token}: ${value}\\b`));
        assert.match(window, new RegExp(`Theme\\.${token}`));
    }
    assert.match(theme, /launcherInitialScale:\s*0\.985/);
    assert.match(window, /Theme\.launcherInitialScale/);
});
