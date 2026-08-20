const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir, load } = require("./shell.cjs");

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
    const providers = read("Common/LauncherProviders.qml");
    const helpers = load("LauncherProviders.js");
    const app = { id: "z.desktop", name: "Zulu", genericName: "", keywords: [] };

    assert.equal(helpers.appScore(app, "", 9000), 1,
        "an empty query must give every app the same score");
    assert.match(providers,
        /ProviderHelpers\.appScore\(app, root\.term,[\s\S]*Launcher\.usageBoost\(app\)\)/);
    assert.match(providers,
        /\.sort\(\(a, b\) => b\.score - a\.score[\s\S]*a\.title\.localeCompare\(b\.title\)\)/);
    assert.match(view, /readonly property var rows:\s*LauncherProviders\.rows/);
});

test("the view is provider-driven and owns no search subprocesses", () => {
    const view = read("LauncherView.qml");
    const providers = read("Common/LauncherProviders.qml");

    assert.match(view, /readonly property var provider:\s*LauncherProviders\.activeProvider/);
    assert.match(view, /LauncherProviders\.query = query/);
    assert.match(view, /LauncherProviders\.activate\(row\)/);
    assert.match(view, /LauncherProviders\.emptyText/);
    assert.match(view, /LauncherProviders\.footerLeft/);
    assert.doesNotMatch(view, /\bProcess\s*\{|\bTimer\s*\{|switch \(row\.kind\)/,
        "providers, not the presentation, own asynchronous work and activation");

    for (const process of ["fileProc", "calcProc", "clipboardListProc"])
        assert.match(providers, new RegExp(`id:\\s*${process}`));
});

test("the launcher defaults to Apps and exposes the discoverable provider tabs", () => {
    const view = read("LauncherView.qml");
    const providers = read("Common/LauncherProviders.qml");

    assert.match(providers, /property string selectedProviderId:\s*"apps"/);
    assert.match(providers,
        /activeProvider:\s*prefixActive\s*\?\s*prefixedProvider\s*:\s*ProviderHelpers\.providerById\(selectedProviderId\)/s);
    assert.match(view, /readonly property var tabs:\s*LauncherProviders\.tabProviders/);
    assert.match(view,
        /apps:\s*"Apps",\s*emoji:\s*"Emoji",\s*clipboard:\s*"History",\s*actions:\s*"Actions"/s);
    assert.match(view,
        /function prepareOpen\(\): void \{\s*LauncherProviders\.selectedProviderId = "apps";/s);
    assert.match(view,
        /function selectTab\(providerId\): void \{\s*LauncherProviders\.selectedProviderId = providerId;\s*search\.text = "";/s);
    assert.match(view, /Qt\.ControlModifier[\s\S]*Qt\.Key_Tab[\s\S]*cycleTab/);
    assert.match(view,
        /Qt\.Key_Left\) \{\s*cycleTab\(-1\);[\s\S]*Qt\.Key_Right\) \{\s*cycleTab\(1\);/);
    assert.doesNotMatch(view,
        /Qt\.NoModifier[\s\S]{0,80}Qt\.Key_(?:Left|Right)/,
        "arrow tab navigation must tolerate compositor keyboard flags");
    assert.match(view, /"←→ tab"/);
    assert.match(view, /Accessible\.role:\s*Accessible\.PageTab/);
});

test("clipboard, emoji, and action providers have installed data sources", () => {
    const providers = read("Common/LauncherProviders.qml");
    const packages = fs.readFileSync(path.resolve(shellDir,
        "../../../apps/defaults/main.yml"), "utf8");
    const actions = JSON.parse(read("launcher-actions.json"));

    assert.match(providers, /wl-paste --type text --watch cliphist store/);
    assert.match(providers, /wl-paste --type image --watch cliphist store/);
    assert.match(providers, /\/usr\/share\/unicode\/emoji\/emoji-test\.txt/);
    assert.match(providers, /watchChanges:\s*true/);
    assert.match(packages, /^\s+- cliphist$/m);
    assert.match(packages, /^\s+- unicode-emoji$/m);
    assert.ok(Array.isArray(actions));
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
