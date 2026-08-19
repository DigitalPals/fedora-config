const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

function read(relative) {
    return fs.readFileSync(path.join(shellDir, relative), "utf8");
}

function qmlFiles(directory) {
    const out = [];
    const walk = current => {
        for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
            const full = path.join(current, entry.name);
            if (entry.isDirectory())
                walk(full);
            else if (entry.name.endsWith(".qml"))
                out.push(full);
        }
    };
    walk(path.join(shellDir, directory));
    return out;
}

test("Appearance exposes live glass, palette, and stored fixed color controls", () => {
    const appearance = read("Settings/AppearancePage.qml");
    const settings = read("Common/Settings.qml");
    const slider = read("Common/HSlider.qml");

    for (const [type, key] of [
        ["bool", "glassEnabled"],
        ["string", "barColorMode"],
        ["int", "barCustomHue"],
        ["int", "barCustomSaturation"],
        ["int", "barCustomLightness"]
    ])
        assert.match(settings, new RegExp(`property ${type} ${key}: defaults\\.${key}`));
    assert.match(settings, /readonly property string effectiveBarColor:/);
    assert.match(settings, /SettingsHelpers\.resolveBarColor/);
    assert.match(settings, /onGlassEnabledChanged:[\s\S]{0,100}?applyGlassEffect\(\)/);

    assert.match(appearance,
        /label:\s*"Glass effect"[\s\S]{0,100}?settingKey:\s*"glassEnabled"/);
    assert.match(appearance, /title:\s*"Colors"/);
    assert.match(appearance,
        /label:\s*"Colors"[\s\S]{0,100}?settingKey:\s*"paletteMode"/);
    assert.match(appearance, /Common\.Palette\.busy/);
    assert.match(appearance, /Common\.Palette\.error/);
    assert.match(appearance, /SectionHeader \{ label:\s*"BAR COLOR" \}/);
    assert.match(appearance, /model:\s*Settings\.barColorChoices/);
    assert.match(appearance, /Accessible\.role:\s*Accessible\.RadioButton/);
    assert.match(appearance, /Accessible\.checked:\s*selected/);
    assert.match(appearance, /Settings\.previewBarColor\(modelData\.id\)/);
    for (const key of ["barCustomHue", "barCustomSaturation", "barCustomLightness"])
        assert.match(appearance, new RegExp(`settingKey: "${key}"`));
    assert.match(appearance, /hueTrack:\s*true/);
    assert.match(appearance, /colorTrack:\s*true/);
    assert.match(appearance, /id:\s*fixedColorReveal[\s\S]{0,100}?reveal:\s*page\.fixedPalette/,
        "wallpaper mode must collapse all fixed choices");
    assert.match(appearance,
        /id:\s*customColorReveal[\s\S]{0,100}?reveal:\s*Settings\.barColorMode === "custom"/,
        "custom HSL controls must be progressively disclosed");
    assert.match(read("Common/Revealer.qml"), /enabled:\s*root\.reveal/,
        "collapsed choices must immediately leave keyboard traversal");
    assert.match(slider, /property bool colorTrack:\s*false/);
    assert.match(slider, /GradientStop \{ position: 0\.5; color: root\.trackMiddle \}/);
});

test("glass switches every shell surface through semantic fills", () => {
    const theme = read("Common/Theme.qml");
    assert.match(theme,
        /readonly property color barSurface:\s*Settings\.glassEnabled[\s\S]{0,150}?: barBg/);
    assert.match(theme,
        /readonly property color surfaceStrong:\s*Settings\.glassEnabled \? glassStrong : popBg/);
    assert.match(theme,
        /readonly property color surfaceMenu:\s*Settings\.glassEnabled \? glassMenu : menuBg/);

    const expected = {
        "Bar/Bar.qml": "barSurface",
        "Bar/PopoutHost.qml": "surfaceStrong",
        "Bar/BarTooltip.qml": "surfaceMenu",
        "LauncherWindow.qml": "surfaceStrong",
        "NotificationToasts.qml": "surfaceStrong",
        "OsdWindow.qml": "surfaceStrong",
        "PowerMenu.qml": "surfaceStrong",
        "ShortcutsOverlay.qml": "surfaceStrong",
        "Popovers/Surface.qml": "surfaceStrong",
        "Popovers/T3Picker.qml": "surfaceMenu",
        "Settings/FolderDialog.qml": "surfaceMenu"
    };
    for (const [file, token] of Object.entries(expected))
        assert.match(read(file), new RegExp(`Theme\\.${token}\\b`),
            `${file} does not follow the glass setting`);

    for (const file of qmlFiles(".")) {
        if (file === path.join(shellDir, "Common", "Theme.qml"))
            continue;
        assert.doesNotMatch(fs.readFileSync(file, "utf8"), /Theme\.glass(?:Strong|Menu)?\b/,
            `${path.relative(shellDir, file)} bypasses the semantic glass tokens`);
    }
    assert.match(read("PowerMenu.qml"), /color:\s*Theme\.scrim/,
        "turning glass off must not remove the modal safety scrim");
});

test("menubar content uses its colour-derived palette", () => {
    const exempt = new Set(["BarTooltip.qml", "PopoutHost.qml"]);
    const globalPalette = /Theme\.(?:glass|chip|chipHover|wsOccupied|dotDim|stroke|icon|textHi|textMid|textLow|textDim|textFaint|accent|accentFg|accentGlow|red|redText|redBg|amber|amberBg|wxSun|wxMoon|wxCloud|wxFog|wxRain|wxSnow|wxStorm)\b/;

    for (const file of qmlFiles("Bar")) {
        if (exempt.has(path.basename(file)))
            continue;
        assert.doesNotMatch(fs.readFileSync(file, "utf8"), globalPalette,
            `${path.relative(shellDir, file)} bypasses the automatic menubar palette`);
    }

    const theme = read("Common/Theme.qml");
    assert.match(theme,
        /readonly property var barPalette:\s*paletteActive[\s\S]{0,180}?SettingsHelpers\.barPalette/);
    assert.match(theme, /readonly property color barAccent:\s*SettingsHelpers\.ensureContrast/);
    assert.match(read("Common/Weather.qml"), /function barGlyphColor/);
    assert.match(read("Bar/Modules/Weather.qml"), /Weather\.barGlyphColor/);
    assert.match(read("Bar/T3Chip.qml"), /colorizationColor:\s*Theme\.barIcon/);
    assert.match(read("Bar/UsageChips.qml"), /colorizationColor:\s*Theme\.barIcon/);
});

test("the named Hyprland blur rule persists and applies without remapping surfaces", () => {
    const look = fs.readFileSync(path.resolve(shellDir, "../looknfeel.lua"), "utf8");
    const settings = read("Common/Settings.qml");

    assert.match(look, /local function persisted_glass_enabled\(\)/);
    assert.match(look, /\[,\{\]%s\*"glassEnabled"%s\*:%s\*\(%a\+\)/);
    assert.match(look,
        /quickshell_blur_rule = hl\.layer_rule\(\{[\s\S]*?enabled = persisted_glass_enabled\(\)/);
    assert.match(look,
        /namespace = \[\[\^qs-\(bar\|bar-popout\|launcher\|notifications\|osd\|power\|shortcuts\)\$\]\]/);
    assert.match(settings,
        /"hyprctl", "eval",[\s\S]{0,120}?"quickshell_blur_rule:set_enabled\("/);
    assert.match(settings, /exitSeen \? lastExit : ProcHelpers\.NOT_STARTED/,
        "a missing hyprctl binary must surface as an apply error");
    assert.match(settings,
        /if \(root\.dispatchedGlassEnabled !== root\.glassEnabled\)\s*glassReplayTimer\.restart\(\)/,
        "a second toggle while hyprctl is busy must be replayed");

    for (const file of ["Bar/Bar.qml", "Bar/BarPopoutWindow.qml", "LauncherWindow.qml",
        "NotificationToasts.qml", "OsdWindow.qml", "PowerMenu.qml", "ShortcutsOverlay.qml"])
        assert.doesNotMatch(read(file), /WlrLayershell\.namespace:\s*Settings\./,
            `${file} must keep a stable namespace when glass changes`);
});
