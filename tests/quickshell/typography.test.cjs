const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir, load } = require("./shell.cjs");

const themePath = path.join(shellDir, "Common", "Theme.qml");
const theme = fs.readFileSync(themePath, "utf8");

// Recursive: the bar's modules live in Bar/Modules/, and a font literal
// hides just as well one directory down.
function qmlFiles(directory) {
    const out = [];
    const walk = dir => {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory() && entry.name !== "tests")
                walk(full);
            else if (entry.name.endsWith(".qml"))
                out.push(full);
        }
    };
    walk(path.join(shellDir, directory));
    return out;
}

function intToken(name) {
    const match = theme.match(new RegExp(`readonly property int ${name}:\\s*(\\d+)`));
    assert.ok(match, `Theme.${name} must be an integer token`);
    return Number(match[1]);
}

function stringToken(name) {
    const match = theme.match(new RegExp(`readonly property string ${name}:\\s*"([^"]+)"`));
    assert.ok(match, `Theme.${name} must be a string token`);
    return match[1];
}

function hexToken(name) {
    const match = theme.match(new RegExp(`readonly property color ${name}:\\s*"(#[0-9a-fA-F]{6})"`));
    assert.ok(match, `Theme.${name} must be a six-digit hex color`);
    return match[1];
}

function luminance(hex) {
    const channels = hex.slice(1).match(/../g).map(value => Number.parseInt(value, 16) / 255);
    const linear = channels.map(value => value <= 0.04045
        ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
}

function contrast(a, b) {
    const lighter = Math.max(luminance(a), luminance(b));
    const darker = Math.min(luminance(a), luminance(b));
    return (lighter + 0.05) / (darker + 0.05);
}

test("semantic typography tokens retain the intended logical-pixel scale", () => {
    // The softer pass removes ten-pixel metadata without inflating body copy.
    assert.deepEqual([
        intToken("fontMicro"),
        intToken("fontTiny"),
        intToken("fontCaption"),
        intToken("fontSecondary"),
        intToken("fontBody"),
        intToken("fontHeading"),
        intToken("fontProminent"),
        intToken("fontDisplay"),
        intToken("fontHero"),
    ], [11, 12, 12, 13, 14, 16, 20, 28, 34]);
});

test("menu typography keeps the bar's own compact metrics", () => {
    assert.equal(stringToken("fontSans"), "Google Sans Flex");
    assert.equal(stringToken("fontIcon"), "Material Symbols Rounded");
    assert.deepEqual([
        intToken("chipHeight"),
        intToken("chipInnerHeight"),
        intToken("tooltipHeight"),
        intToken("barTextSize"),
        intToken("barIconSize"),
    ], [32, 26, 28, 13, 16]);
    assert.match(theme, /readonly property var tabularNumberFeatures:\s*\(\{\s*"tnum":\s*1\s*\}\)/);
});

test("settings-driven tokens default to the softer menu face", () => {
    // fontMenu / barHeight / clusterRadius moved from literals to Shell
    // settings bindings; the defaults must still reproduce the design values
    // and Theme must actually bind to Settings rather than re-hardcode.
    const H = load("SettingsHelpers.js");
    const d = H.defaults();
    assert.equal(d.barHeight, 46);
    assert.equal(d.barRadius, 23);
    assert.equal(d.gap, 10);
    assert.equal(d.barStyle, "hug");
    assert.equal(d.accent, "#5e9bff");
    const menuChoice = H.FONT_CHOICES.find(choice => choice.id === d.font);
    assert.equal(menuChoice.family, "Google Sans Flex");

    assert.match(theme, /readonly property int barHeight:\s*Settings\.barHeight/);
    assert.match(theme, /readonly property bool barFloating:\s*Settings\.barStyle === "floating"/);
    assert.match(theme, /readonly property int clusterRadius:\s*barFloating \? Settings\.barRadius : 0/);
    assert.match(theme, /readonly property color accent:\s*paletteActive \? Common\.Palette\.primary/);
    assert.match(theme, /Settings\.fontChoices/);
    // Derived accent fills must track the dynamic accent, not a literal.
    assert.doesNotMatch(theme, /158 \/ 255/);
    assert.match(theme, /readonly property color accentSoft:\s*paletteActive/);
});

test("shared surfaces carry the roomier density tokens", () => {
    assert.deepEqual([
        intToken("popWidth"),
        intToken("popWideWidth"),
        intToken("surfacePadding"),
        intToken("rowHeight"),
        intToken("tileHeight"),
    ], [408, 448, 16, 52, 64]);
});

test("the menu face is scoped to shell chrome while T3 keeps its product face", () => {
    for (const file of [...qmlFiles("Bar"), ...qmlFiles("Popovers"), ...qmlFiles("Settings")]) {
        const source = fs.readFileSync(file, "utf8");
        const label = path.relative(shellDir, file);
        if (/^Popovers\/T3.*\.qml$/.test(label)) {
            assert.match(source, /T3Theme\.fontSans/,
                `${label} must use the stable T3 product face`);
            assert.doesNotMatch(source, /Theme\.fontMenu/,
                `${label} must not inherit the user-selected shell menu face`);
        } else {
            assert.doesNotMatch(source, /(?<!T3)Theme\.fontSans/,
                `${label} bypasses Theme.fontMenu`);
        }
    }

    for (const name of ["LauncherView.qml", "NotificationToasts.qml"]) {
        const source = fs.readFileSync(path.join(shellDir, name), "utf8");
        assert.match(source, /Theme\.fontSans/, `${name} must retain the general UI face`);
        assert.doesNotMatch(source, /Theme\.fontMenu/, `${name} must remain outside menu typography`);
    }
});

test("all visible bar values use the menu face with tabular figures", () => {
    for (const file of qmlFiles("Bar")) {
        const source = fs.readFileSync(file, "utf8");
        const label = path.relative(shellDir, file);
        assert.doesNotMatch(source, /font\.family:\s*Theme\.fontMono/,
            `${label} still uses the monospace face`);
    }

    // Every bar file that draws a changing number. The four modules joined
    // the list when Bar.qml stopped drawing any of them itself.
    for (const name of ["BarIcon.qml", "T3Chip.qml", "UsageChips.qml", "Workspaces.qml",
                        "Modules/Clock.qml", "Modules/Weather.qml",
                        "Modules/Battery.qml", "Modules/Volume.qml"]) {
        const source = fs.readFileSync(path.join(shellDir, "Bar", name), "utf8");
        assert.match(source, /Theme\.tabularNumberFeatures/,
            `${name} must opt dynamic values into tabular figures`);
    }
});

test("bar and popovers use semantic sizes with an eleven-pixel text floor", () => {
    const files = [...qmlFiles("Bar"), ...qmlFiles("Popovers"), ...qmlFiles("Settings")];
    const textTokens = [...theme.matchAll(/readonly property int (font\w+):\s*(\d+)/g)];
    assert.ok(textTokens.length > 0);
    for (const [, name, value] of textTokens)
        assert.ok(Number(value) >= 11, `Theme.${name} falls below the 11 px floor`);

    for (const file of files) {
        const source = fs.readFileSync(file, "utf8");
        const label = path.relative(shellDir, file);
        assert.doesNotMatch(source, /font\.pixelSize:\s*\d+(?:\.\d+)?/,
            `${label} contains a raw numeric text size`);
        assert.doesNotMatch(source, /font-size\s*:/i,
            `${label} contains an inline HTML text size`);
        assert.doesNotMatch(source, /font\.weight:\s*\d+/,
            `${label} contains a weight that does not map to an installed face`);
    }
});

test("soft shell chrome does not use the display-heavy text weight", () => {
    // Google Sans Flex makes 750 conspicuous at compact shell sizes. Keep the
    // token available for a deliberate future display treatment, but require
    // current chrome to express hierarchy with medium, semibold, or bold.
    for (const file of qmlFiles(".")) {
        const source = fs.readFileSync(file, "utf8");
        const label = path.relative(shellDir, file);
        assert.doesNotMatch(source, /Theme\.weightHeavy/,
            `${label} uses the display-heavy weight in shell chrome`);
    }
});

test("no surface that floats over the desktop draws a drop shadow", () => {
    // The compositor blurs the whole layer, and each of these layers is bigger
    // than the shape it draws. A shadow painted into that margin is blurred
    // with it and reads as a haze band the height of the surface, not as a
    // shadow. Glows *inside* a surface composite over the glass and are fine —
    // hence the allow-list rather than a blanket ban.
    const insideASurface = [
        "Bar/T3Chip.qml",            // the running dot's bloom, inside the bar
        "Bar/Workspaces.qml",        // the focused pip's bloom, inside the bar
        "Settings/ModulesPage.qml"   // the drag proxy, over an opaque page
    ];
    const offenders = [];
    for (const file of [...qmlFiles("Bar"), ...qmlFiles("Popovers"),
                        ...qmlFiles("Settings"),
                        ...["LauncherWindow.qml", "LauncherView.qml",
                            "NotificationToasts.qml", "OsdWindow.qml",
                            "PowerMenu.qml", "ShortcutsOverlay.qml"]
                            .map(name => path.join(shellDir, name))]) {
        const label = path.relative(shellDir, file);
        if (insideASurface.includes(label))
            continue;
        if (/RectangularShadow/.test(fs.readFileSync(file, "utf8")))
            offenders.push(label);
    }
    assert.deepEqual(offenders, []);
});

test("views paint semantic surfaces rather than their opaque variants", () => {
    // `popBg`/`barBg` are selected by Theme's semantic aliases in solid mode
    // and serve as fixed contrast references in glass mode. Painting one in a
    // view would bypass the Glass effect switch.
    //
    // `Settings/` is exempt: its bar and toast previews are *pictures of*
    // those surfaces, and its drag proxy floats over the settings page.
    const offenders = [];
    for (const file of [...qmlFiles("Bar"), ...qmlFiles("Popovers"),
                        ...["LauncherWindow.qml", "LauncherView.qml",
                            "NotificationToasts.qml", "OsdWindow.qml",
                            "PowerMenu.qml", "ShortcutsOverlay.qml"]
                            .map(name => path.join(shellDir, name))]) {
        const label = path.relative(shellDir, file);
        fs.readFileSync(file, "utf8").split("\n").forEach((line, index) => {
            if (/^\s*color:\s*Theme\.(popBg|barBg)\s*$/.test(line))
                offenders.push(`${label}:${index + 1}`);
        });
    }
    assert.deepEqual(offenders, [],
        "these bypass the semantic glass/solid surface token");
});

test("low-emphasis text remains WCAG AA in both palettes", () => {
    // Glass has no fixed background, so contrast is checked against the opaque
    // reference each palette declares: what a panel reads as over the shell's
    // own dimmed wallpaper. The design's own low tone lands at 3.2:1 there,
    // which is why these are lifted rather than copied.
    for (const mode of ["dark", "light"]) {
        const background = hexToken(`${mode}PopBg`);
        for (const step of ["TextMid", "TextLow", "TextDim", "TextFaint", "Icon"]) {
            const name = mode + step;
            assert.ok(contrast(hexToken(name), background) >= 4.5,
                `Theme.${name} must have at least 4.5:1 contrast against ${mode}PopBg`);
        }
    }
    // The one decorative token, and the reason the others cannot be lowered
    // to meet the design: it exists so nothing else has to be.
    assert.match(theme, /\/\/ Decorative only[\s\S]*?readonly property color dotDim/);
});
