const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const shellDir = path.resolve(__dirname, "../..");

// Every directory holding QML types, discovered rather than listed. A
// directory carrying a qmldir is no longer implicitly scanned by the
// engine, so an unlisted type fails at runtime as "X is not a type" —
// which is why this check exists at all.
//
// Derived on purpose: this list used to be hardcoded, and when Bar/Modules/
// was added it escaped every assertion below until someone noticed. A new
// directory of types now joins the check by existing.
function typeDirs() {
    const out = [];
    const walk = (rel) => {
        const abs = path.join(shellDir, rel);
        const entries = fs.readdirSync(abs, { withFileTypes: true });
        if (entries.some(e => e.isFile() && /^[A-Z].*\.qml$/.test(e.name)))
            out.push(rel);
        for (const e of entries) {
            if (e.isDirectory() && !e.name.startsWith(".")
                    && !["tests", "assets", "scripts"].includes(e.name))
                walk(rel === "." ? e.name : path.join(rel, e.name));
        }
    };
    walk(".");
    return out;
}

const DIRS = typeDirs();

// Files that must NOT be registered as types, with the reason. A stale
// exemption is itself a failure: see the test below.
const EXEMPT = {
    "Common/T3Socket.qml":
        "imports the optional QtWebSockets package; T3Code loads it through a "
        + "Loader by URL so a missing package degrades to Loader.Error instead "
        + "of an unresolvable type"
};

function read(relative) {
    return fs.readFileSync(path.join(shellDir, relative), "utf8");
}

function qmlFilesIn(dir) {
    return fs.readdirSync(path.join(shellDir, dir))
        .filter(name => name.endsWith(".qml"))
        // A QML type name must start uppercase, so a lowercase file can never
        // be one. That is exactly shell.qml, the entry point loaded by path.
        .filter(name => /^[A-Z]/.test(name));
}

// `Type File.qml` or `singleton Type File.qml`, ignoring comments.
function entriesIn(dir) {
    const out = new Map();
    for (const line of read(path.join(dir, "qmldir")).split("\n")) {
        const trimmed = line.trim();
        if (trimmed === "" || trimmed.startsWith("#"))
            continue;
        const parts = trimmed.split(/\s+/);
        const [type, file] = parts[0] === "singleton" ? [parts[1], parts[2]] : parts;
        out.set(file, type);
    }
    return out;
}

test("every directory that needs a qmldir has one", () => {
    assert.ok(DIRS.length >= 5, `only found ${DIRS.length} type directories`);
    for (const dir of DIRS)
        assert.ok(fs.existsSync(path.join(shellDir, dir, "qmldir")),
            `${dir}/qmldir is missing`);
});

test("every QML type is listed in its directory's qmldir", () => {
    for (const dir of DIRS) {
        const entries = entriesIn(dir);
        const files = qmlFilesIn(dir);
        assert.ok(files.length > 0, `${dir} has no QML types — did it move?`);
        for (const file of files) {
            const rel = dir === "." ? file : `${dir}/${file}`;
            if (EXEMPT[rel] !== undefined) {
                assert.equal(entries.has(file), false,
                    `${rel} is exempt (${EXEMPT[rel]}) but ${dir}/qmldir lists it`);
                continue;
            }
            assert.ok(entries.has(file), `${dir}/qmldir must list ${file}`);
            assert.equal(entries.get(file), file.replace(/\.qml$/, ""),
                `${dir}/qmldir registers ${file} under the wrong type name`);
        }
    }
});

test("every qmldir entry points at a file that exists", () => {
    for (const dir of DIRS) {
        for (const [file, type] of entriesIn(dir)) {
            assert.ok(fs.existsSync(path.join(shellDir, dir, file)),
                `${dir}/qmldir lists ${file}, which does not exist`);
            assert.ok(/^[A-Z]/.test(type), `${dir}/qmldir type ${type} must start uppercase`);
        }
    }
});

test("shell.qml is not registered as a type anywhere", () => {
    // It is the entry point Quickshell loads by path. Listing it would also be
    // impossible — QML type names cannot start lowercase.
    for (const dir of DIRS)
        assert.equal(entriesIn(dir).has("shell.qml"), false,
            `${dir}/qmldir must not list shell.qml`);
    assert.ok(fs.existsSync(path.join(shellDir, "shell.qml")));
});

test("every exemption still exists and still says why", () => {
    // A file that was exempt and then deleted, or exempted without a reason,
    // would otherwise quietly weaken this check.
    for (const [rel, reason] of Object.entries(EXEMPT)) {
        assert.ok(fs.existsSync(path.join(shellDir, rel)),
            `${rel} is exempted but no longer exists — drop the exemption`);
        assert.ok(reason.length > 20, `${rel} needs a real reason`);
        const dir = path.dirname(rel);
        assert.match(read(path.join(dir, "qmldir")), /^#/m,
            `${dir}/qmldir must carry a comment explaining its exemption`);
    }
});

test("T3Socket stays reachable by URL, since it is not a type", () => {
    // The exemption is only safe while this is how it loads.
    assert.match(read("Common/T3Code.qml"), /source:\s*"T3Socket\.qml"/);
});
