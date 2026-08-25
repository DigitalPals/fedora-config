const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./shell.cjs");

const P = load("LauncherProviders.js");

test("provider registry preserves every launcher mode and adds palette providers", () => {
    assert.deepEqual(P.PROVIDERS.map(provider => provider.id), [
        "files", "command", "calculator", "web", "windows",
        "clipboard", "emoji", "actions", "apps"
    ]);
    assert.equal(P.providerFor("firefox").id, "apps");
    assert.equal(P.providerFor("/notes").id, "files");
    assert.equal(P.providerFor(";deploy token").id, "clipboard");
    assert.equal(P.providerFor(":rocket").id, "emoji");
    assert.equal(P.providerFor("!wallpaper").id, "actions");
    assert.equal(P.prefixedProviderFor("firefox"), null);
    assert.equal(P.prefixedProviderFor(":rocket").id, "emoji");
    assert.deepEqual(P.TAB_IDS, ["apps", "emoji", "clipboard", "actions"]);
    assert.equal(P.termFor(";  deploy token  "), "deploy token");
    assert.equal(new Set(P.PROVIDERS.map(provider => provider.prefix)).size,
        P.PROVIDERS.length, "prefixes must be unique, including the default");
});

test("clearing a prefix restores the selected tab provider", () => {
    const selectedTab = "clipboard";

    assert.equal(P.prefixedProviderFor(":rocket").id, "emoji");
    assert.equal(P.prefixedProviderFor(""), null);
    assert.equal(P.providerById(selectedTab).id, "clipboard");
});

test("app scoring keeps an empty directory alphabetical and adds usage later", () => {
    const app = {
        id: "org.mozilla.firefox.desktop",
        name: "Firefox",
        genericName: "Web Browser",
        keywords: ["internet", "browser"]
    };

    assert.equal(P.appScore(app, "", 9000), 1);
    assert.equal(P.appScore(app, "fire", 12), 8012);
    assert.equal(P.appScore(app, "browser", 12), 6012);
    assert.equal(P.appScore(app, "internet", 12), 6012);
    assert.equal(P.appScore(app, "terminal", 12), -1);
});

test("clipboard rows retain the opaque cliphist entry and recognize images", () => {
    const rows = P.clipboardRows([
        "41\tsecond text",
        "42\t[[ binary data 1920x1080 png ]]",
        "43\tdeploy token"
    ], "", 8);

    assert.equal(rows.length, 3);
    assert.equal(rows[0].raw, "41\tsecond text");
    assert.equal(rows[1].image, true);
    assert.equal(rows[1].title, "Clipboard image");
    assert.deepEqual(P.clipboardRows(rows.map(row => row.raw), "deploy", 8)
        .map(row => row.raw), ["43\tdeploy token"]);
});

test("emoji parser accepts only fully-qualified entries and searches names", () => {
    const source = [
        "1F600 ; fully-qualified # 😀 E1.0 grinning face",
        "1F3F3 FE0F 200D 1F308 ; fully-qualified # 🏳️‍🌈 E4.0 rainbow flag",
        "263A ; unqualified # ☺ E0.6 smiling face"
    ].join("\n");
    const entries = P.parseEmojiData(source);

    assert.deepEqual(entries, [
        { emoji: "😀", name: "grinning face" },
        { emoji: "🏳️‍🌈", name: "rainbow flag" }
    ]);
    assert.deepEqual(P.emojiRows(entries, "rainbow", 8)
        .map(row => row.value), ["🏳️‍🌈"]);
});

test("user actions require a name and argv command and cannot inject glyphs", () => {
    const parsed = P.parseActions(JSON.stringify([
        {
            id: "project",
            name: "Open project",
            subtitle: "Launch an editor",
            keywords: ["code", "work"],
            glyph: "untrusted_icon",
            command: ["code", "/tmp/project"]
        },
        { name: "Missing command" },
        { name: "String command", command: "rm -rf /" },
        { id: "project", name: "Duplicate", command: ["true"] }
    ]));

    assert.equal(parsed.error, "");
    assert.equal(parsed.actions.length, 1);
    assert.equal(parsed.actions[0].id, "user-project");
    assert.deepEqual(parsed.actions[0].command, ["code", "/tmp/project"]);
    assert.equal(parsed.actions[0].glyph, "bolt");
    assert.deepEqual(P.actionRows(parsed.actions, "work", 8)
        .map(row => row.title), ["Open project"]);
    assert.deepEqual(P.actionRows(parsed.actions, "editor", 8)
        .map(row => row.title), ["Open project"],
        "subtitles remain searchable even though the view does not draw them");
    assert.notEqual(P.parseActions("{").error, "");
    assert.notEqual(P.parseActions("{}").error, "");
});
