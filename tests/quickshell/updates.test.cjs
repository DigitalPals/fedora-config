const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir, load } = require("./shell.cjs");

const H = load("UpdatesHelpers.js");

function read(relative) {
    return fs.readFileSync(path.join(shellDir, relative), "utf8");
}

test("dnf output keeps real package rows and their raw multiarch count", () => {
    const output = [
        "Updating and loading repositories:",
        "Repositories loaded.",
        "SDL3.i686                 3.2.22-1.fc44 updates",
        "SDL3.x86_64               3.2.22-1.fc44 updates",
        "python3-foo+bar.noarch     1.4-2.fc44    updates",
        "  a continuation that is not a package"
    ].join("\n");

    assert.deepEqual(H.dnfNames(output), ["SDL3", "SDL3", "python3-foo+bar"]);
    assert.deepEqual(H.dnfNames(""), []);
});

test("Flatpak output drops blank rows without changing application names", () => {
    assert.deepEqual(H.flatpakNames("Firefox\n  Spotify  \n\n"),
        ["Firefox", "Spotify"]);
    assert.deepEqual(H.flatpakNames(undefined), []);
});

test("only a complete post-baseline zero-to-positive transition notifies", () => {
    assert.equal(H.shouldNotify(true, true, 0, 3, true), true);
    assert.equal(H.shouldNotify(true, false, 0, 3, true), false,
        "the first successful snapshot establishes the baseline silently");
    assert.equal(H.shouldNotify(false, true, 0, 3, true), false,
        "a partial failure cannot announce a half-result");
    assert.equal(H.shouldNotify(true, true, 2, 3, true), false,
        "a count that merely grows is not a new update event");
    assert.equal(H.shouldNotify(true, true, 0, 3, false), false);
});

test("the QML coordinator settles both commands, including start failures", () => {
    const updates = read("Common/Updates.qml");
    const popover = read("Popovers/UpdatesPopover.qml");

    assert.match(updates, /readonly property bool busy: !dnfDone \|\| !flatpakDone/);
    assert.match(updates, /function finishCheck\(\) \{\s*if \(!dnfDone \|\| !flatpakDone\)\s*return;/);
    assert.equal((updates.match(/ProcHelpers\.NOT_STARTED/g) || []).length, 2,
        "both commands need the no-exited-signal fallback");
    assert.equal((updates.match(/onRunningChanged:/g) || []).length >= 3, true,
        "both processes and the recheck timer should have completion handling");
    assert.doesNotMatch(updates, /onTotalChanged:/,
        "intermediate per-process totals must not drive notifications");
    assert.match(updates, /command: \["timeout", "45s"/,
        "a background poll must have a finite upper bound");
    assert.match(popover, /Accessible\.name:[\s\S]{0,100}?Check for updates/);
    assert.match(popover, /onClicked:[\s\S]{0,100}?Updates\.check\(\)/);
});
