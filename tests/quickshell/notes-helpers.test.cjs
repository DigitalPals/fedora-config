const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./shell.cjs");

const H = load("NotesHelpers.js");

function note(id, body, createdAt, updatedAt, title = H.fallbackTitle(body)) {
    return { id, title, body, createdAt, updatedAt };
}

function legacyNote(id, body, createdAt, updatedAt) {
    return { id, body, createdAt, updatedAt };
}

test("Notes state parsing is strict and preserves raw Markdown", () => {
    assert.equal(H.VERSION, 2);
    for (const empty of ["", "  \n", null, undefined])
        assert.equal(H.parseState(empty).status, "corrupt",
            "an existing empty state file must not be silently replaced");

    const body = "  # Heading\n\n- item  \n`code`\n";
    const parsed = H.parseState(JSON.stringify({
        v: 2,
        notes: [note("stable-id", body, 10, 20)]
    }));
    assert.equal(parsed.status, "ok");
    assert.equal(parsed.records[0].body, body,
        "leading, trailing, and Markdown-significant whitespace must survive");
});

test("malformed, duplicate, and invalid records block the complete state", () => {
    const valid = note("one", "body", 1, 2);
    const corrupt = [
        "{broken",
        JSON.stringify([]),
        JSON.stringify({ v: 3, notes: [] }),
        JSON.stringify({ v: 2 }),
        JSON.stringify({ v: 2, notes: [], extra: true }),
        JSON.stringify({ v: 2, notes: "not-an-array" }),
        JSON.stringify({ v: 2, notes: [valid, valid] }),
        JSON.stringify({ v: 2, notes: [note("", "body", 1, 2)] }),
        JSON.stringify({ v: 2, notes: [note("one", " \n\t", 1, 2)] }),
        JSON.stringify({ v: 2, notes: [note("one", "body", -1, 2)] }),
        JSON.stringify({ v: 2, notes: [note("one", "body", 3, 2)] }),
        JSON.stringify({ v: 2, notes: [note("one", "body", 1, 2, "")] }),
        JSON.stringify({ v: 2, notes: [note("one", "body", 1, 2, " bad ")] }),
        JSON.stringify({ v: 1, notes: [{ ...legacyNote("one", "body", 1, 2),
            title: "unexpected" }] })
    ];
    for (const state of corrupt)
        assert.equal(H.parseState(state).status, "corrupt", state);
    assert.equal(H.validRecord(note("one", "body", 0, Number.NaN)), false);
    assert.equal(H.parseState(JSON.stringify({
        v: 2,
        notes: [note("toString", "valid inherited-key id", 1, 2)]
    })).status, "ok");
});

test("schema-v1 notes migrate locally with exact content and timestamps", () => {
    const body = "\n> ## Project **Atlas**\n\n- second line\n";
    const old = legacyNote("legacy", body, 12, 34);
    const parsed = H.parseState(JSON.stringify({ v: 1, notes: [old] }));
    assert.equal(parsed.status, "ok");
    assert.equal(parsed.migrated, true);
    assert.deepEqual(parsed.records, [note("legacy", body, 12, 34, "Project Atlas")]);
    assert.equal(JSON.parse(H.serializeState(parsed.records)).v, 2);
});

test("Markdown fallback titles are plain, bounded, and deterministic", () => {
    assert.equal(H.fallbackTitle("\n```md\n# **Roadmap** and [docs](https://x)\n"),
        "Roadmap and docs");
    assert.equal(H.fallbackTitle("- [ ] Acheter du lait"), "Acheter du lait");
    assert.equal(H.fallbackTitle("---\n~~~\n"), "Untitled note");
    assert.equal(H.fallbackTitle(`# ${"x".repeat(80)}`).length, 50);
    assert.equal(H.validTitle("One line"), true);
    for (const invalid of ["", " spaced ", "two\nlines", "x".repeat(51)])
        assert.equal(H.validTitle(invalid), false, invalid);
});

test("new notes never copy body text into their title", () => {
    const added = H.addRecord([], "Body starts here", "new-id", 10, "");
    assert.equal(added.record.title, H.UNTITLED_TITLE);

    const edited = H.updateRecord(added.records, "new-id", "A different body", 20);
    assert.equal(edited.record.title, H.UNTITLED_TITLE);
});

test("only an empty title with a configured provider auto-generates", () => {
    assert.equal(H.shouldAutoGenerateTitle("", "codex"), true);
    assert.equal(H.shouldAutoGenerateTitle("  \n", "claude"), true);
    assert.equal(H.shouldAutoGenerateTitle("Written title", "codex"), false);
    assert.equal(H.shouldAutoGenerateTitle("", "off"), false);
});

test("serialization has fixed keys and deterministic timestamp ordering", () => {
    const older = note("z", "older", 1, 4);
    const tiedSecond = note("b", "second tie", 2, 8);
    const tiedFirst = note("a", "first tie", 2, 8);
    const records = [older, tiedSecond, tiedFirst];
    assert.deepEqual(H.sortRecords(records).map(record => record.id), ["a", "b", "z"]);

    const one = H.serializeState(records);
    const two = H.serializeState([tiedFirst, older, tiedSecond]);
    assert.equal(one, two);
    assert.equal(one, JSON.stringify({
        v: 2,
        notes: [tiedFirst, tiedSecond, older]
    }, null, 2) + "\n");
    assert.deepEqual(H.parseState(one).records,
        [tiedFirst, tiedSecond, older]);
});

test("editing updates the timestamp and moves a note to the top", () => {
    const records = [note("newer", "new", 10, 30), note("older", "old", 5, 20)];
    const changed = H.updateRecord(records, "older", "**edited**", 40);
    assert.equal(changed.changed, true);
    assert.deepEqual(changed.records.map(record => record.id), ["older", "newer"]);
    assert.deepEqual(changed.records[0],
        note("older", "**edited**", 5, 40, "old"));
    assert.equal(records[1].body, "old", "helpers must not mutate the live model in place");

    const same = H.updateRecord(changed.records, "older", "**edited**", 50);
    assert.equal(same.changed, false, "focus changes alone must not rewrite timestamps");
    assert.equal(same.records[0].updatedAt, 40);
});

test("manual titles update edit time while generated titles do not", () => {
    const original = note("id", "# Body", 10, 20, "Body");
    const manual = H.updateTitleRecord([original], "id", "  My   title  ", 30);
    assert.equal(manual.changed, true);
    assert.deepEqual(manual.record, note("id", "# Body", 10, 30, "My title"));

    const cleared = H.updateTitleRecord(manual.records, "id", "", 40);
    assert.deepEqual(cleared.record,
        note("id", "# Body", 10, 40, H.UNTITLED_TITLE));

    const generated = H.applyGeneratedTitle([original], "id", "AI title");
    assert.equal(generated.changed, true);
    assert.deepEqual(generated.record, note("id", "# Body", 10, 20, "AI title"));
});

test("title request guards reject stale body, title, provider, model, and effort", () => {
    const original = note("id", "Body", 10, 20, "Local title");
    const request = H.captureTitleRequest(original, "codex", "gpt-5.6-luna", "low");
    assert.ok(request);
    assert.equal(H.titleRequestCurrent([original], request,
        "codex", "gpt-5.6-luna", "low"), true);
    assert.equal(H.titleRequestCurrent([
        { ...original, body: "Changed" }
    ], request, "codex", "gpt-5.6-luna", "low"), false);
    assert.equal(H.titleRequestCurrent([
        { ...original, title: "Manual" }
    ], request, "codex", "gpt-5.6-luna", "low"), false);
    assert.equal(H.titleRequestCurrent([original], request,
        "claude", "fable", "low"), false);
    assert.equal(H.titleRequestCurrent([original], request,
        "codex", "gpt-5.6", "low"), false);
    assert.equal(H.titleRequestCurrent([original], request,
        "codex", "gpt-5.6-luna", "high"), false);
    assert.equal(H.titleRequestCurrent([], request,
        "codex", "gpt-5.6-luna", "low"), false);
    assert.equal(H.captureTitleRequest(original,
        "claude", "fable", "none"), null);
});

test("blank drafts delete existing notes but never create empty new notes", () => {
    const records = [note("keep", "Raw Markdown", 10, 20)];
    const untouched = H.commitDraft(records, "", " \n\t", 30, "new-id");
    assert.equal(untouched.changed, false);
    assert.deepEqual(untouched.records, records);

    const deleted = H.commitDraft(records, "keep", "\n  ", 30, "unused");
    assert.equal(deleted.changed, true);
    assert.deepEqual(deleted.records, []);
    assert.deepEqual(deleted.deleted, records[0]);
});

test("Undo restores the exact deleted id, body, and timestamps", () => {
    const original = note("stable-id", "  *raw*\n", 12, 34, "Handwritten title");
    const removed = H.removeRecord([original], original.id);
    const restored = H.restoreDeleted(removed.records, removed.deleted);
    assert.equal(restored.changed, true);
    assert.deepEqual(restored.records, [original]);
    assert.notEqual(restored.records[0], original, "restoration returns an independent record");
    assert.equal(H.restoreDeleted(restored.records, original).changed, false,
        "Undo cannot introduce a duplicate id");
});

test("inline Markdown actions wrap selections and place empty cursors", () => {
    assert.deepEqual(H.transformMarkdown("hello", 0, 5, "bold"), {
        text: "**hello**", selectionStart: 2, selectionEnd: 7, cursorPosition: 7
    });
    assert.deepEqual(H.transformMarkdown("ab", 1, 1, "italic"), {
        text: "a__b", selectionStart: 2, selectionEnd: 2, cursorPosition: 2
    });
    assert.deepEqual(H.transformMarkdown("x", 0, 1, "code"), {
        text: "`x`", selectionStart: 1, selectionEnd: 2, cursorPosition: 2
    });

    const selectedLink = H.transformMarkdown("OpenAI", 0, 6, "link");
    assert.equal(selectedLink.text, "[OpenAI](https://)");
    assert.equal(selectedLink.text.slice(selectedLink.selectionStart,
        selectedLink.selectionEnd), "https://");
    const emptyLink = H.transformMarkdown("", 0, 0, "link");
    assert.equal(emptyLink.text, "[link text](https://)");
    assert.equal(emptyLink.text.slice(emptyLink.selectionStart,
        emptyLink.selectionEnd), "link text");
});

test("list actions toggle all selected lines without stacking prefixes", () => {
    const bullets = H.transformMarkdown("one\ntwo", 0, 7, "bullet");
    assert.equal(bullets.text, "- one\n- two");
    assert.equal(H.transformMarkdown(bullets.text, 0, bullets.text.length, "bullet").text,
        "one\ntwo");

    const checklist = H.transformMarkdown("- one\n* two", 0, 11, "checklist");
    assert.equal(checklist.text, "- [ ] one\n- [ ] two");
    assert.equal(H.transformMarkdown(checklist.text, 0, checklist.text.length,
        "checklist").text, "one\ntwo");

    const atCursor = H.transformMarkdown("item", 2, 2, "bullet");
    assert.equal(atCursor.text, "- item");
    assert.equal(atCursor.cursorPosition, 4);
});
