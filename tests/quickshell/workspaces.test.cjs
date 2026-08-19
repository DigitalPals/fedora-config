const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

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
