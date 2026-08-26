const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./shell.cjs");

const H = load("BatteryViewHelpers.js");

test("battery capacity is formatted in Wh with a stable decimal", () => {
    assert.equal(H.formatWh(55.234), "55.2 Wh");
    assert.equal(H.formatWh("86"), "86.0 Wh");
});

test("battery rate is an absolute W value and keeps an idle reading", () => {
    assert.equal(H.formatW(12.26), "12.3 W");
    assert.equal(H.formatW(-7.94), "7.9 W");
    assert.equal(H.formatW(0), "0.0 W");
});

test("missing and malformed battery telemetry stays visibly unavailable", () => {
    for (const value of [undefined, null, "", "unknown", NaN, Infinity]) {
        assert.equal(H.formatWh(value), "—");
        assert.equal(H.formatW(value), "—");
        assert.equal(H.formatDuration(value), "—");
    }
    assert.equal(H.formatWh(0), "—");
    assert.equal(H.formatWh(-1), "—");
    assert.equal(H.formatDuration(0), "—");
    assert.equal(H.formatDuration(-60), "—");
});

test("battery estimates format minutes and normalized hour boundaries", () => {
    assert.equal(H.formatDuration(45), "1 min");
    assert.equal(H.formatDuration(59 * 60 + 40), "1 h 00 min");
    assert.equal(H.formatDuration(2 * 60 * 60 + 5 * 60), "2 h 05 min");
});

test("a single battery cycle count is normalized", () => {
    assert.equal(H.parseCycleCounts("0042\n"), "42");
});

test("multiple battery cycle counts remain sorted output separated by dots", () => {
    assert.equal(H.parseCycleCounts("42\n317\n"), "42 · 317");
});

test("missing and malformed cycle output uses stable placeholders", () => {
    assert.equal(H.parseCycleCounts(""), "—");
    assert.equal(H.parseCycleCounts(undefined), "—");
    assert.equal(H.parseCycleCounts("not-a-count\n"), "—");
    assert.equal(H.parseCycleCounts("42\nnot-a-count\n"), "42 · —");
});
