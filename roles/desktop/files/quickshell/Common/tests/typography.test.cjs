const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const shellDir = path.resolve(__dirname, "../..");
const themePath = path.join(shellDir, "Common", "Theme.qml");
const theme = fs.readFileSync(themePath, "utf8");

function qmlFiles(directory) {
    return fs.readdirSync(path.join(shellDir, directory))
        .filter(name => name.endsWith(".qml"))
        .map(name => path.join(shellDir, directory, name));
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
    assert.deepEqual([
        intToken("fontCaption"),
        intToken("fontSecondary"),
        intToken("fontBody"),
        intToken("fontHeading"),
        intToken("fontProminent"),
        intToken("fontDisplay"),
        intToken("fontHero"),
    ], [12, 13, 14, 16, 20, 28, 34]);
});

test("menu typography is OPPO Sans and retains compact macOS-like metrics", () => {
    assert.equal(stringToken("fontSans"), "IBM Plex Sans");
    assert.deepEqual([
        intToken("chipHeight"),
        intToken("tooltipHeight"),
        intToken("chipRadius"),
        intToken("barTextSize"),
        intToken("barIconSize"),
    ], [24, 26, 6, 13, 14]);
    assert.match(theme, /readonly property var tabularNumberFeatures:\s*\(\{\s*"tnum":\s*1\s*\}\)/);
});

test("settings-driven tokens default to the original menu metrics", () => {
    // fontMenu / barHeight / clusterRadius moved from literals to Shell
    // settings bindings; the defaults must still reproduce the design values
    // and Theme must actually bind to Settings rather than re-hardcode.
    const H = require("../SettingsHelpers.js");
    const d = H.defaults();
    assert.equal(d.barHeight, 30);
    assert.equal(d.barRadius, 9);
    assert.equal(d.gap, 8);
    assert.equal(d.floating, true);
    assert.equal(d.accent, "#9ecbeb");
    const menuChoice = H.FONT_CHOICES.find(choice => choice.id === d.font);
    assert.equal(menuChoice.family, "OPPO Sans 4.0");

    assert.match(theme, /readonly property int barHeight:\s*Settings\.barHeight/);
    assert.match(theme, /readonly property int clusterRadius:\s*Settings\.floating\s*\?\s*Settings\.barRadius\s*:\s*0/);
    assert.match(theme, /readonly property color accent:\s*Settings\.effectiveAccent/);
    assert.match(theme, /Settings\.fontChoices/);
    // Derived accent fills must track the dynamic accent, not the old literal.
    assert.doesNotMatch(theme, /158 \/ 255/);
});

test("OPPO Sans is scoped to the bar and its popovers", () => {
    for (const file of [...qmlFiles("Bar"), ...qmlFiles("Popovers"), ...qmlFiles("Settings")]) {
        const source = fs.readFileSync(file, "utf8");
        const label = path.relative(shellDir, file);
        assert.doesNotMatch(source, /Theme\.fontSans/, `${label} bypasses Theme.fontMenu`);
    }

    for (const name of ["LauncherView.qml", "NotificationToasts.qml"]) {
        const source = fs.readFileSync(path.join(shellDir, name), "utf8");
        assert.match(source, /Theme\.fontSans/, `${name} must retain the general UI face`);
        assert.doesNotMatch(source, /Theme\.fontMenu/, `${name} must remain outside menu typography`);
    }
});

test("all visible bar values use OPPO Sans with tabular figures", () => {
    for (const file of qmlFiles("Bar")) {
        const source = fs.readFileSync(file, "utf8");
        const label = path.relative(shellDir, file);
        assert.doesNotMatch(source, /font\.family:\s*Theme\.fontMono/,
            `${label} still uses the monospace face`);
    }

    for (const name of ["Bar.qml", "BarIcon.qml", "T3Chip.qml", "UsageChips.qml", "Workspaces.qml"]) {
        const source = fs.readFileSync(path.join(shellDir, "Bar", name), "utf8");
        assert.match(source, /Theme\.tabularNumberFeatures/,
            `${name} must opt dynamic values into tabular figures`);
    }
});

test("bar and popovers use semantic sizes with a twelve-pixel text floor", () => {
    const files = [...qmlFiles("Bar"), ...qmlFiles("Popovers"), ...qmlFiles("Settings")];
    const textTokens = [...theme.matchAll(/readonly property int (font\w+):\s*(\d+)/g)];
    assert.ok(textTokens.length > 0);
    for (const [, name, value] of textTokens)
        assert.ok(Number(value) >= 12, `Theme.${name} falls below the 12 px floor`);

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

test("low-emphasis text remains WCAG AA against the shared dark surface", () => {
    const background = hexToken("popBg");
    for (const name of ["textLow", "textDim", "textFaint"])
        assert.ok(contrast(hexToken(name), background) >= 4.5,
            `Theme.${name} must have at least 4.5:1 contrast against Theme.popBg`);
});
