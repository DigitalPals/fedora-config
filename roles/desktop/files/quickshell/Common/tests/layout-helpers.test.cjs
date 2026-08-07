const test = require("node:test");
const assert = require("node:assert/strict");

const H = require("../LayoutHelpers.js");

test("stacked drops subtract each column origin before finding the row", () => {
    const columns = [
        { id: "left", y: 0, height: 90, rowsStart: 20, pitch: 31, length: 2 },
        { id: "center", y: 98, height: 121, rowsStart: 20, pitch: 31, length: 3 },
        { id: "right", y: 227, height: 152, rowsStart: 20, pitch: 31, length: 4 }
    ];
    assert.deepEqual(H.stackedDropIndex(columns, 120), { col: "center", idx: 0 });
    assert.deepEqual(H.stackedDropIndex(columns, 174), { col: "center", idx: 2 });
    assert.deepEqual(H.stackedDropIndex(columns, 999), { col: "right", idx: 4 });
});

test("wide measured layouts remain detailed and centered", () => {
    const result = H.fitBar({
        width: 1440, sideMargin: 12, gutter: 8,
        widths: { left: 220, center: 240, right: 390 },
        entries: [
            { id: "media", col: "left", saving: 120, policy: "auto" },
            { id: "weather", col: "center", saving: 70, policy: "auto" }
        ]
    });
    assert.deepEqual(result.compact, []);
    assert.equal(result.centerOffset, 0);
    assert.equal(result.fits, true);
});

test("measured fitting compacts auto detail before prefer-detail", () => {
    const result = H.fitBar({
        width: 800, gutter: 8,
        widths: { left: 260, center: 220, right: 310 },
        entries: [
            { id: "media", col: "left", saving: 60, policy: "prefer" },
            { id: "weather", col: "center", saving: 30, policy: "auto" },
            { id: "clock", col: "center", saving: 45, policy: "auto" },
            { id: "t3", col: "right", saving: 60, policy: "auto" }
        ]
    });
    assert.deepEqual(result.compact.slice(0, 2), ["weather", "clock"]);
    assert.equal(result.compact.includes("media"), false);
    assert.equal(result.fits, true);
});

test("forced compact modules stay present and the center shifts last", () => {
    const result = H.fitBar({
        width: 800, gutter: 8,
        widths: { left: 330, center: 180, right: 250 },
        entries: [
            { id: "media", col: "left", saving: 20, policy: "compact" },
            { id: "weather", col: "center", saving: 10, policy: "auto" }
        ]
    });
    assert.ok(result.compact.includes("media"));
    assert.ok(result.compact.includes("weather"));
    assert.equal(result.fits, true);
    assert.equal(result.shifted, true);
    assert.ok(result.widths.left + 8 <= result.centerX);
    assert.ok(result.centerX + result.widths.center + 8
        <= 800 - result.widths.right);
});

test("all-auto detail follows the documented compaction order", () => {
    const entries = [
        { id: "usage", col: "right", saving: 20, policy: "auto" },
        { id: "batt", col: "right", saving: 20, policy: "auto" },
        { id: "vol", col: "right", saving: 20, policy: "auto" },
        { id: "t3", col: "right", saving: 20, policy: "auto" },
        { id: "clock", col: "center", saving: 20, policy: "auto" },
        { id: "weather", col: "center", saving: 20, policy: "auto" },
        { id: "media", col: "left", saving: 20, policy: "auto" }
    ];
    const result = H.fitBar({
        width: 800, gutter: 8,
        widths: { left: 390, center: 300, right: 390 },
        entries
    });
    assert.deepEqual(result.compact, H.COMPACT_ORDER);
    assert.equal(entries.length, 7, "fitting changes detail, not module enablement");
});

test("high resolution wheel deltas emit only accumulated steps", () => {
    let accumulator = 0;
    let steps = 0;
    for (let i = 0; i < 4; i++) {
        const result = H.accumulateWheel(accumulator, 30, 120);
        accumulator = result.accumulator;
        steps += result.steps;
    }
    assert.equal(steps, 1);
    assert.equal(accumulator, 0);
    assert.deepEqual(H.accumulateWheel(0, -240, 120), { accumulator: 0, steps: -2 });
});
