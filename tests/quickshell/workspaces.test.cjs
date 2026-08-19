const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir, load } = require("./shell.cjs");

const Motion = load("WorkspaceMotion.js");

function read(rel) {
    return fs.readFileSync(path.join(shellDir, rel), "utf8");
}

test("occupied workspaces stay visibly distinct from empty slots", () => {
    const workspaces = read("Bar/Workspaces.qml");
    const theme = read("Common/Theme.qml");

    assert.match(workspaces,
        /root\.numbered\s*\?\s*\(exists\s*\?\s*Theme\.barChipHover\s*:\s*Theme\.barChip\)/,
        "numbered slots need separate occupied and empty fills");
    assert.match(workspaces, /exists\s*\?\s*Theme\.barWsOccupied\s*:\s*Theme\.barDotDim/,
        "dot slots need a dedicated occupied tone");
    assert.match(theme, /readonly property color barWsOccupied:/,
        "the occupied state must be a semantic theme token");
    assert.match(workspaces, /exists\s*\?\s*", occupied"\s*:\s*", empty"/,
        "assistive output must announce the same distinction shown visually");
});

test("workspace cells and hide-empty geometry stay deterministic", () => {
    assert.equal(Motion.CELL_WIDTH, 22);
    assert.deepEqual(Motion.visibleIds(5, [1, 3], 1, false), [1, 2, 3, 4, 5]);
    assert.deepEqual(Motion.visibleIds(5, [1, 3], 1, true), [1, 3]);
    assert.deepEqual(Motion.visibleIds(5, [1, 3], 4, true), [1, 3, 4]);
    assert.deepEqual(Motion.indicatorBounds([1, 3, 4], 3), { left: 24, right: 42 });
    assert.equal(Motion.indicatorBounds([1, 3], 2), null);
});

test("the lozenge assigns 120ms to its leading and 300ms to trailing edge", () => {
    assert.deepEqual(Motion.edgeDurations(2, 5, true), {
        left: 300, right: 120, direction: 1
    });
    assert.deepEqual(Motion.edgeDurations(5, 2, true), {
        left: 120, right: 300, direction: -1
    });
    assert.deepEqual(Motion.edgeDurations(2, 5, false), {
        left: 0, right: 0, direction: 0
    });
    assert.deepEqual(Motion.edgeDurations(-1, 2, true), {
        left: 0, right: 0, direction: 0
    });
});

test("the pager snaps structural changes and animates only focus transitions", () => {
    const workspaces = read("Bar/Workspaces.qml");
    assert.match(workspaces, /width:\s*WorkspaceMotion\.CELL_WIDTH/);
    assert.match(workspaces, /height:\s*30/);
    assert.match(workspaces, /property real leftEdge/);
    assert.match(workspaces, /property real rightEdge/);
    assert.match(workspaces, /Behavior on leftEdge/);
    assert.match(workspaces, /Behavior on rightEdge/);
    assert.match(workspaces, /onStructureKeyChanged:[\s\S]{0,100}?snapRequested = true/);
    assert.match(workspaces,
        /function onModOptsChanged\(\)[\s\S]{0,100}?snapRequested = true/);
    assert.match(workspaces, /Component\.onCompleted:[\s\S]{0,140}?settleIndicator\(false\)/);
    assert.match(workspaces, /Accessible\.onPressAction/);
    assert.match(workspaces, /Theme\.barRed/);
    assert.match(workspaces, /visible:\s*root\.numbered/);
});
