const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

// A `Connections` handler whose name matches nothing on the target is not an
// error anywhere: qmllint has no opinion, the configuration loads, and
// Quickshell logs one WARN at reload and then never calls it. The code reads
// as wired and simply does nothing.
//
// The T3 façade makes this easy to hit. Views only ever talk to T3Code, which
// re-exports the split singletons' state, so a handler for something that
// still lives on T3Drafts/T3Detail looks right at both ends. It has shipped
// three times now: threadDrafts and userInputDrafts (a composer that would not
// re-render), newThreadConfirmed (a new thread never opened) and
// detailThreadId (a thread page that kept the previous thread's scroll
// position and message window).

function qmlFiles(dir, found = []) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory() && !entry.name.startsWith(".")
                && !["tests", "assets", "scripts"].includes(entry.name))
            qmlFiles(full, found);
        else if (entry.name.endsWith(".qml"))
            found.push(full);
    }
    return found;
}

// Strings before comments, so a stripped string cannot look like the start of
// one, and neither can shift the brace depth below.
function strip(source) {
    return source
        .replace(/"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'/g, '""')
        .replace(/\/\/[^\n]*/g, "");
}

// Text at the immediate level of a block, nested objects removed, so a nested
// Connections' target is never read as this one's.
function topLevel(body) {
    let previous;
    do {
        previous = body;
        body = body.replace(/\{[^{}]*\}/g, " ");
    } while (body !== previous);
    return body;
}

function blocksOf(source, pattern) {
    const found = [];
    for (const match of source.matchAll(pattern)) {
        const start = match.index + match[0].length - 1;
        let depth = 0;
        let end = start;
        while (end < source.length) {
            if (source[end] === "{")
                depth++;
            else if (source[end] === "}" && --depth === 0)
                break;
            end++;
        }
        found.push({
            body: source.slice(start + 1, end),
            line: source.slice(0, match.index).split("\n").length,
        });
    }
    return found;
}

// What each singleton actually answers to: a declared signal `foo` is reached
// as `onFoo`, and a property `foo` gets a generated `fooChanged` reached as
// `onFooChanged`.
function singletonSurfaces() {
    const surfaces = {};
    for (const file of qmlFiles(path.join(shellDir, "Common"))) {
        const raw = fs.readFileSync(file, "utf8");
        if (!/pragma Singleton/.test(raw))
            continue;
        const source = strip(raw);
        surfaces[path.basename(file, ".qml")] = {
            properties: new Set([...source.matchAll(/\bproperty\s+(?:list<)?[\w.<>]+>?\s+(\w+)/g)]
                .map(m => m[1])),
            signals: new Set([...source.matchAll(/^\s*signal\s+(\w+)/gm)].map(m => m[1])),
        };
    }
    return surfaces;
}

test("every Connections handler on a singleton matches something it emits", () => {
    const surfaces = singletonSurfaces();
    assert.ok(Object.keys(surfaces).length > 15,
        "the singleton scan found almost nothing, so the check below proves nothing");

    const dead = [];
    for (const file of qmlFiles(shellDir)) {
        const source = strip(fs.readFileSync(file, "utf8"));
        for (const block of blocksOf(source, /\bConnections\s*\{/g)) {
            const head = topLevel(block.body);
            const target = head.match(/\btarget:\s*([A-Za-z_][\w.]*)/);
            // Only singleton targets resolve statically; `target: root` and
            // friends depend on what the id is bound to at runtime.
            const surface = target ? surfaces[target[1]] : undefined;
            if (!surface)
                continue;
            for (const handler of head.matchAll(/\bfunction\s+(on[A-Z]\w*)\s*\(/g)) {
                const name = handler[1];
                const member = name[2].toLowerCase() + name.slice(3);
                if (surface.signals.has(member)
                        || (member.endsWith("Changed")
                            && surface.properties.has(member.slice(0, -"Changed".length))))
                    continue;
                dead.push(`${path.relative(shellDir, file)}:~${block.line} `
                    + `${target[1]}.${name}`);
            }
        }
    }
    assert.deepEqual(dead, [],
        "these handlers are never called; re-export the member on the façade");
});
