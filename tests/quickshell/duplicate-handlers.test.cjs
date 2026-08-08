const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

// qmllint does not catch this, and the failure is total: QML reports
// "Property value set multiple times", the whole configuration fails to load,
// and Quickshell keeps running the last good copy — so the shell looks fine
// while every edit since is silently not applied. It bit three times in one
// session, twice in throwaway probes and once in Bar.qml's own onWidthChanged.
//
// Scoped to declarations at the same brace depth inside the same object, which
// is what QML actually forbids; the same handler name on nested children is
// ordinary and must not trip this.

function qmlFiles() {
    const out = [];
    const walk = dir => {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory() && !entry.name.startsWith(".")
                    && !["tests", "assets", "scripts"].includes(entry.name))
                walk(full);
            else if (entry.name.endsWith(".qml"))
                out.push(full);
        }
    };
    walk(shellDir);
    return out;
}

// Track (depth, memberName) pairs, resetting a depth's set whenever a new
// object opens at that depth. Strings and comments are skipped so a brace or
// a colon inside either cannot shift the depth.
function duplicateMembers(source) {
    const seen = new Map();      // depth -> Set of member names
    const dupes = [];
    let depth = 0;
    let line = 1;

    const lines = source.split("\n");
    for (const raw of lines) {
        const text = raw.replace(/\/\/.*$/, "").replace(/"(\\.|[^"\\])*"/g, '""');

        // A member declaration is `name:` at the start of a line. Handlers and
        // plain property bindings both take this form.
        const match = text.match(/^\s*(on[A-Z]\w*|[a-z]\w*(?:\.\w+)*)\s*:/);
        if (match) {
            const name = match[1];
            if (!seen.has(depth))
                seen.set(depth, new Set());
            if (seen.get(depth).has(name))
                dupes.push({ line, name, depth });
            else
                seen.get(depth).add(name);
        }

        for (const ch of text) {
            if (ch === "{") {
                depth++;
                seen.set(depth, new Set());   // a new object body at this depth
            } else if (ch === "}") {
                seen.delete(depth);
                depth--;
            }
        }
        line++;
    }
    return dupes;
}

test("no object sets the same property or handler twice", () => {
    const offenders = [];
    for (const file of qmlFiles()) {
        for (const d of duplicateMembers(fs.readFileSync(file, "utf8")))
            offenders.push(`${path.relative(shellDir, file)}:${d.line} sets ${d.name} twice`);
    }
    assert.deepEqual(offenders, []);
});

test("the check finds a duplicate the linter lets through", () => {
    // The exact shape that broke Bar.qml: two handlers for one signal on the
    // same object, with an unrelated nested object in between.
    const broken = [
        "Item {",
        "    onWidthChanged: doThing()",
        "    Rectangle {",
        "        onWidthChanged: fine()",
        "    }",
        "    onWidthChanged: doOtherThing()",
        "}"
    ].join("\n");
    const found = duplicateMembers(broken);
    assert.equal(found.length, 1, "the outer duplicate must be reported");
    assert.equal(found[0].name, "onWidthChanged");
    assert.equal(found[0].line, 6);
});

test("the check does not fire on separate sibling objects", () => {
    const fine = [
        "Row {",
        "    Rectangle { width: 1 }",
        "    Rectangle { width: 2 }",
        "    Text { color: \"#fff\" }",
        "    Text { color: \"#000\" }",
        "}"
    ].join("\n");
    assert.deepEqual(duplicateMembers(fine), []);
});

test("a brace or colon inside a string does not shift the depth", () => {
    const tricky = [
        "Item {",
        "    text: \"a { brace and a : colon\"",
        "    color: \"#fff\"",
        "}"
    ].join("\n");
    assert.deepEqual(duplicateMembers(tricky), []);
});
