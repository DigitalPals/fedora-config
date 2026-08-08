// The T3 client is split across sibling singletons (T3Connection, T3Rpc,
// T3Threads, T3Detail, T3Drafts, T3Git, T3Code). A function body in one that
// names another's property *unqualified* is not an error to qmllint — the
// Singleton root type keeps it from resolving the scope — but it throws
// ReferenceError the first time the function runs, invisibly to everything
// but the journal. WP5.1 and WP5.2 both shipped that bug; a third instance
// (threadMap and the supports* flags in T3Rpc) is what prompted this test.
//
// So: every name on the watchlist below must, in any Common/T3*.qml that does
// not declare it, appear only qualified (`T3Threads.threadMap`, never bare
// `threadMap`). The list is the cross-singleton state worth reaching for, not
// every property — short generic names (state, host, threads) would collide
// with locals and drown the check in false positives.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

const WATCHLIST = [
    "threadMap",
    "projectMap",
    "supportsSettlement",
    "supportsSnooze",
    "supportsTitleRegeneration",
    "supportsPinning",
    "actionStates",
    "rpcHandlers",
    "environmentCapabilities",
    "providerConfigurations",
    "detailThreadId",
    "detailReqId",
    "pinnedThreads",
    "snoozedThreads",
    "settledThreads",
    "newThreadDraft",
    "threadDrafts",
    "userInputDrafts",
];

const commonDir = path.join(shellDir, "Common");
const files = fs.readdirSync(commonDir)
    .filter(name => /^T3.*\.qml$/.test(name));

function stripCommentsAndStrings(source) {
    return source
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .replace(/\/\/[^\n]*/g, "")
        .replace(/"(?:[^"\\\n]|\\.)*"/g, '""')
        .replace(/'(?:[^'\\\n]|\\.)*'/g, "''")
        .replace(/`(?:[^`\\]|\\.)*`/g, "``");
}

function declaredNames(source) {
    const names = new Set();
    for (const match of source.matchAll(
        /^\s*(?:readonly\s+)?(?:default\s+)?property\s+\S+\s+(\w+)/gm))
        names.add(match[1]);
    for (const match of source.matchAll(/^\s*function\s+(\w+)\s*\(/gm))
        names.add(match[1]);
    return names;
}

test("T3 singletons never reach for another singleton's state unqualified", () => {
    assert.ok(files.length >= 6, "expected the T3 singleton family in Common/");
    const offences = [];
    for (const name of files) {
        const source = fs.readFileSync(path.join(commonDir, name), "utf8");
        const declared = declaredNames(source);
        const scannable = stripCommentsAndStrings(source);
        const lines = scannable.split("\n");
        for (const watched of WATCHLIST) {
            if (declared.has(watched))
                continue;
            const bare = new RegExp("(^|[^.\\w])" + watched + "\\b");
            lines.forEach((line, index) => {
                if (bare.test(line))
                    offences.push(`${name}:${index + 1} bare \`${watched}\`: ${line.trim()}`);
            });
        }
    }
    assert.deepEqual(offences, [],
        "unqualified cross-singleton access throws ReferenceError at runtime:\n"
        + offences.join("\n"));
});
