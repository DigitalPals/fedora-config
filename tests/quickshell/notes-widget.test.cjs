const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir, load } = require("./shell.cjs");

const Settings = load("SettingsHelpers.js");
const Catalog = load("WidgetCatalog.js");
const Registry = load("PanelRegistryData.js");

function read(relative) {
    return fs.readFileSync(path.join(shellDir, relative), "utf8");
}

test("schema 20 enables Notes immediately after Weather", () => {
    assert.equal(Settings.VERSION, 20);
    const center = Settings.defaultMods().center;
    const weather = center.findIndex(entry => entry.id === "weather");
    assert.equal(center[weather + 1].id, "notes");
    assert.equal(center[weather + 1].on, true);
    assert.equal(Settings.moduleGroup("notes", Settings.defaultModOpts()), "solo");
    assert.deepEqual(Catalog.WIDGETS.notes, { name: "Notes", short: "Notes" });
});

test("schema-19 migration follows Weather without changing another widget", () => {
    const oldIds = Settings.MODULE_IDS.filter(id => id !== "notes");
    const entries = oldIds.map((id, index) => ({
        id,
        on: index % 2 === 0,
        detail: ["compact", "prefer", "auto"][index % 3]
    }));
    const weather = entries.find(entry => entry.id === "weather");
    const raw = {
        left: entries.slice(0, 3),
        center: entries.slice(3, 4),
        right: entries.slice(4)
    };
    raw.left.push(raw.right.splice(raw.right.indexOf(weather), 1)[0]);

    const migrated = Settings.merge({ v: 19, mods: raw }).mods;
    for (const col of ["left", "center", "right"])
        assert.deepEqual(migrated[col].filter(entry => entry.id !== "notes"), raw[col]);
    const weatherIndex = migrated.left.findIndex(entry => entry.id === "weather");
    assert.deepEqual(migrated.left[weatherIndex + 1],
        { id: "notes", on: true, detail: "auto" });
});

test("Notes owns one center popout and every loader/index knows it", () => {
    assert.deepEqual(Registry.byName("notes"), {
        name: "notes",
        island: "center",
        moduleId: "notes",
        source: "Popovers/NotesPopover.qml"
    });
    assert.equal(Registry.panelForModule("notes"), "notes");
    assert.equal(Registry.NOTES, "notes");
    assert.match(read("Bar/Bar.qml"), /notes:\s*"Modules\/Notes\.qml"/);
    assert.match(read("Common/qmldir"), /^singleton Notes Notes\.qml$/m);
    assert.match(read("Bar/Modules/qmldir"), /^Notes Notes\.qml$/m);
    assert.match(read("Popovers/qmldir"), /^NotesPopover NotesPopover\.qml$/m);
});

test("the bar widget is icon-only and its tooltip owns the count", () => {
    const module = read("Bar/Modules/Notes.qml");
    assert.match(module, /moduleId:\s*"notes"/);
    assert.match(module, /panelName:\s*"notes"/);
    assert.match(module, /glyph:\s*"sticky_note_2"/);
    assert.match(module, /label:\s*""/);
    assert.match(module, /tooltip:\s*Notes\.count/);
    assert.doesNotMatch(module, /Text\s*\{/,
        "the menubar must not render a label or count beside the icon");
});

test("Notes persistence is strict, atomic, debounced, queued, and retryable", () => {
    const notes = read("Common/Notes.qml");
    for (const property of ["records", "ready", "saving", "error", "undoAvailable"])
        assert.match(notes, new RegExp(`property[^\\n]*${property}|property ${property}`));
    for (const fn of ["add", "update", "remove", "undoDelete", "retrySave"])
        assert.match(notes, new RegExp(`function ${fn}\\(`));
    assert.match(notes, /\.local\/state\/quickshell\/notes\.json/);
    assert.match(notes, /atomicWrites:\s*true/);
    assert.match(notes, /blockWrites:\s*true/);
    assert.match(notes, /id:\s*saveTimer[\s\S]*?interval:\s*400/);
    assert.match(notes, /changedWhileSaving[\s\S]*?saveTimer\.restart\(\)/,
        "edits made during a write must queue another snapshot");
    assert.match(notes, /status === "corrupt"[\s\S]*?ready = false/);
    assert.match(notes, /errorKind !== "load"/,
        "a malformed file must close every mutation path");
});

test("the popover exposes editing, formatting, previews, safe links, and Undo", () => {
    const panel = read("Popovers/NotesPopover.qml");
    assert.match(panel, /text:\s*"Notes"/);
    assert.match(panel, /actionName:\s*"Add note"/);
    assert.match(panel, /Accessible\.role:\s*Accessible\.EditableText/);
    for (const action of ["bold", "italic", "bullet", "checklist", "link", "code"])
        assert.match(panel, new RegExp(`applyFormat\\("${action}"\\)`));
    assert.match(panel, /textFormat:\s*Text\.MarkdownText/);
    assert.match(panel, /maximumLineCount:\s*6/);
    assert.match(panel, /id:\s*noteList[\s\S]*?visible:\s*Notes\.count > 0/,
        "the list must not create a visibility/implicit-height cycle");
    assert.match(panel, /id:\s*noteEdit[\s\S]*?activeFocusOnTab:\s*true/,
        "the active editor must remain in the keyboard focus chain");
    assert.match(panel, /ExternalUrl\.safeHttpUrl/);
    assert.match(panel, /Quickshell\.execDetached\(\["xdg-open", safe\]\)/);
    assert.match(panel, /visible:\s*modelData\.id !== root\.editingId/,
        "an active note's preview must be hidden behind its full-source editor");
    assert.ok((panel.match(/actionName:\s*"Delete note"/g) || []).length >= 2,
        "both cards and the existing-note editor need visible trash actions");
    assert.match(panel, /function deleteCard\([\s\S]*?focusInitial\(\)/,
        "deleting a focused card must return keyboard focus to Add");
    assert.match(panel, /label:\s*"Undo"[\s\S]*?Notes\.undoDelete\(\)/);
    assert.match(panel, /label:\s*"Retry"[\s\S]*?Notes\.retrySave\(\)/);
    assert.match(panel, /function handleEscape\(\): bool[\s\S]*?finishEditing\(true\)/);
    assert.match(panel, /onActiveFocusChanged:[\s\S]*?finishEditing\(false\)/,
        "leaving the composer focus scope must finish and flush the edit");
    assert.match(panel,
        /lostGeneration[\s\S]*?editorGeneration === lostGeneration/,
        "a deferred focus exit must not close a newly selected note");
    assert.match(panel, /Component\.onDestruction:\s*finishEditing\(false\)/);
});
