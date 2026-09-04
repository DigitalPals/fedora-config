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

test("schema 22 enables Notes immediately after Weather with opt-in title settings", () => {
    assert.equal(Settings.VERSION, 22);
    const center = Settings.defaultMods().center;
    const weather = center.findIndex(entry => entry.id === "weather");
    assert.equal(center[weather + 1].id, "notes");
    assert.equal(center[weather + 1].on, true);
    assert.equal(Settings.moduleGroup("notes", Settings.defaultModOpts()), "solo");
    assert.deepEqual(Settings.defaultModOpts().notes, {
        titleProvider: "off",
        codexModel: "gpt-5.6-luna",
        codexEffort: "none",
        claudeModel: "fable",
        claudeEffort: "low"
    });
    assert.equal(Settings.merge({ v: 20, modOpts: {
        notes: { titleProvider: "codex", codexModel: "gpt-5.6-luna" }
    } }).modOpts.notes.titleProvider, "off",
    "a pre-provider schema must not accidentally opt in");
    const migrated = Settings.merge({ v: 21, modOpts: {
        notes: { titleProvider: "codex", codexModel: "gpt-5.6-terra" }
    } }).modOpts.notes;
    assert.equal(migrated.titleProvider, "codex");
    assert.equal(migrated.codexModel, "gpt-5.6-terra");
    assert.equal(migrated.codexEffort, "none");
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

test("Notes persistence and title generation are independently queued and retryable", () => {
    const notes = read("Common/Notes.qml");
    for (const property of ["records", "ready", "saving", "error", "undoAvailable"])
        assert.match(notes, new RegExp(`property[^\\n]*${property}|property ${property}`));
    for (const fn of ["add", "update", "updateTitle", "remove", "undoDelete",
        "retrySave", "requestTitle", "retryTitle", "titlePending", "titleError"])
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
    assert.match(notes, /property var titleQueue:\s*\[\]/);
    assert.doesNotMatch(notes, /finishInitialTitle|initialTitleIds/,
        "closing a new note must never request a title automatically");
    assert.match(notes,
        /titleRequestCurrent\(records, request, provider,[\s\S]*?titleModel\(provider\), titleEffort\(provider\)\)/,
        "provider, model, effort, body, and title changes must stale a result");
    assert.match(notes, /effort:\s*request\.effort/);
    assert.match(notes, /body:\s*request\.body\.slice\(0, 12000\)/);
    assert.match(notes, /command:\s*\["python3", Quickshell\.shellDir \+ "\/scripts\/note-title\.py"\]/);
    assert.match(notes, /stderr:\s*StdioCollector\s*\{\}/,
        "CLI diagnostics must not be copied into the shell journal");
    assert.match(notes, /dirty = parsed\.migrated === true[\s\S]*?saveTimer\.restart\(\)/,
        "a valid v1 file must be rewritten atomically as v2");
});

test("the popover exposes title-only cards, editing, generation state, and Undo", () => {
    const panel = read("Popovers/NotesPopover.qml");
    const finishEditing = panel.slice(panel.indexOf("function finishEditing"),
        panel.indexOf("function deleteEditing"));
    assert.match(panel, /text:\s*"Notes"/);
    assert.match(panel, /actionName:\s*"Add note"/);
    assert.match(panel, /Accessible\.role:\s*Accessible\.EditableText/);
    for (const action of ["bold", "italic", "bullet", "checklist", "link", "code"])
        assert.match(panel, new RegExp(`applyFormat\\("${action}"\\)`));
    assert.match(panel,
        /id:\s*titleEdit[\s\S]*?maximumLength:\s*NotesHelpers\.MAX_TITLE_LENGTH/);
    assert.match(panel, /Accessible\.name:\s*"Note title"/);
    assert.match(panel, /label:\s*"Generate"/);
    assert.match(panel,
        /visible:\s*root\.editingId !== ""[\s\S]*?Settings\.modOpts\.notes\.titleProvider !== "off"/,
        "Generate is offered only after a note exists and a provider is configured");
    assert.match(panel, /Notes\.requestTitle\(root\.editingId\)/);
    assert.match(panel, /label:\s*"Retry title"[\s\S]*?Notes\.retryTitle/);
    assert.match(panel, /text:\s*noteCard\.modelData\.title/);
    assert.match(panel, /Generating title…/);
    assert.match(panel, /Accessible\.AlertMessage/,
        "persistence and generation failures must be announced accessibly");
    assert.doesNotMatch(panel, /id:\s*notePreview|Text\.MarkdownText/,
        "the overview must not render note-body excerpts");
    assert.match(panel, /id:\s*noteList[\s\S]*?visible:\s*Notes\.count > 0/,
        "the list must not create a visibility/implicit-height cycle");
    assert.match(panel, /id:\s*noteEdit[\s\S]*?activeFocusOnTab:\s*true/,
        "the active editor must remain in the keyboard focus chain");
    assert.doesNotMatch(panel, /modelData\.body|ExternalUrl/,
        "the overview must expose only stored titles");
    assert.match(panel, /visible:\s*modelData\.id !== root\.editingId/,
        "an active note's preview must be hidden behind its full-source editor");
    assert.ok((panel.match(/actionName:\s*"Delete note"/g) || []).length >= 2,
        "both cards and the existing-note editor need visible trash actions");
    assert.match(panel, /function deleteCard\([\s\S]*?focusInitial\(\)/,
        "deleting a focused card must return keyboard focus to Add");
    assert.match(panel, /label:\s*"Undo"[\s\S]*?Notes\.undoDelete\(\)/);
    assert.match(panel, /label:\s*"Retry"[\s\S]*?Notes\.retrySave\(\)/);
    assert.doesNotMatch(panel, /Saving…|Saved/,
        "ordinary background saves must not show visual confirmation");
    assert.match(panel, /function handleEscape\(\): bool[\s\S]*?finishEditing\(true\)/);
    assert.match(panel, /onActiveFocusChanged:[\s\S]*?finishEditing\(false\)/,
        "leaving the composer focus scope must finish and flush the edit");
    assert.match(panel,
        /lostGeneration[\s\S]*?editorGeneration === lostGeneration/,
        "a deferred focus exit must not close a newly selected note");
    assert.match(panel, /Component\.onDestruction:\s*finishEditing\(false\)/);
    assert.match(panel, /property string observedTitle:\s*""/);
    assert.match(panel, /property bool persistingTitle:\s*false/);
    assert.match(panel, /observedTitle = note \? note\.title : ""/,
        "persisting the first body edit may observe the stored title without filling the input");
    assert.match(panel,
        /if \(!persistingTitle && titleEdit\.text !== note\.title\)[\s\S]*?setEditorTitle\(note\.title\)/,
        "a generated title must reach the separate input even if it still owns focus");
    assert.doesNotMatch(panel,
        /persistEditor\(\)[\s\S]*?if \(!titleTouched\)[\s\S]*?syncEditorTitle/,
        "body persistence must not mirror a fallback into the title input");
    assert.match(panel, /visible:\s*titleEdit\.text === ""[\s\S]*?text:\s*"Title"/);
    assert.doesNotMatch(panel, /Title from the first line/);
    assert.match(finishEditing,
        /shouldAutoGenerateTitle\([\s\S]*?titleEdit\.text,[\s\S]*?Settings\.modOpts\.notes\.titleProvider\)/,
        "closing an untitled editor must require an explicitly configured provider");
    assert.match(finishEditing,
        /Notes\.update\(id, body\);[\s\S]*?if \(autoGenerateTitle\)[\s\S]*?Notes\.requestTitle\(id\)/,
        "the latest body must persist before background title generation starts");
});

test("Notes widget settings expose provider-specific model and effort selectors", () => {
    const detail = read("Settings/ModuleDetailView.qml");
    const search = read("Common/SettingsSearchData.js");
    const notesOptions = detail.slice(detail.indexOf("id: notesOptions"),
        detail.indexOf("id: t3Options"));
    assert.match(detail, /case "notes": return notesOptions/);
    assert.match(detail,
        /id:\s*notesOptions[\s\S]*?label:\s*"Title provider"[\s\S]*?value:\s*"off", label:\s*"Off"[\s\S]*?value:\s*"codex", label:\s*"Codex CLI"[\s\S]*?value:\s*"claude", label:\s*"Claude Code CLI"/);
    assert.match(detail,
        /label:\s*"Codex model"[\s\S]*?model:\s*SettingsHelpers\.NOTE_CODEX_MODEL_CHOICES[\s\S]*?current:\s*view\.opts\.codexModel/);
    assert.match(detail,
        /label:\s*"Claude model"[\s\S]*?model:\s*SettingsHelpers\.NOTE_CLAUDE_MODEL_CHOICES[\s\S]*?current:\s*view\.opts\.claudeModel/);
    assert.match(detail,
        /model:\s*SettingsHelpers\.NOTE_CODEX_EFFORT_CHOICES[\s\S]*?current:\s*view\.opts\.codexEffort/);
    assert.match(detail,
        /model:\s*SettingsHelpers\.NOTE_CLAUDE_EFFORT_CHOICES[\s\S]*?current:\s*view\.opts\.claudeEffort/);
    assert.deepEqual(Settings.NOTE_CODEX_MODEL_CHOICES.map(choice => choice.value),
        ["gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol"]);
    assert.deepEqual(Settings.NOTE_CLAUDE_MODEL_CHOICES.map(choice => choice.value),
        ["fable", "sonnet", "opus"]);
    assert.deepEqual(Settings.NOTE_CODEX_EFFORT_CHOICES.map(choice => choice.value),
        ["none", "low", "medium", "high", "xhigh", "max"]);
    assert.deepEqual(Settings.NOTE_CLAUDE_EFFORT_CHOICES.map(choice => choice.value),
        ["low", "medium", "high", "xhigh", "max"]);
    assert.doesNotMatch(notesOptions, /SettingsTextRow/,
        "model and effort values must be selected, not typed");
    assert.match(detail,
        /sent when you click Generate or leave a note untitled, up to 12,000 characters/);
    assert.match(search, /AI note titles[\s\S]*?codex claude model provider effort/);
});
