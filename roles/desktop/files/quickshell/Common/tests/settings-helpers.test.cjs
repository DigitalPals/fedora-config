const test = require("node:test");
const assert = require("node:assert/strict");

const H = require("../SettingsHelpers.js");

test("defaults carry the design values", () => {
    const d = H.defaults();
    assert.equal(d.barHeight, 30);
    assert.equal(d.barRadius, 9);
    assert.equal(d.font, "oppo");
    assert.equal(d.accent, "#9ecbeb");
    assert.equal(d.position, "top");
    assert.equal(d.floating, true);
    assert.equal(d.gap, 8);
    assert.equal(d.autoHide, false);
    assert.equal(d.exclusive, true);
    assert.equal(d.monitor, "All");
    assert.equal(d.clock24, true);
    assert.equal(d.unit, "c");
    assert.equal(d.warmth, 3400);
    assert.equal(d.osd, "top");
    assert.equal(d.pollMax, 300);
    assert.equal(d.shuffle, "Off");
    assert.deepEqual(d.mods.left.map(m => m.id), ["ws", "media"]);
    assert.deepEqual(d.mods.center.map(m => m.id), ["clock", "weather"]);
    assert.deepEqual(d.mods.right.map(m => m.id),
        ["t3", "vol", "wifi", "batt", "bell", "bt", "idle", "control"]);
    assert.equal(d.mods.left[1].on, false);
    assert.equal(d.mods.right[5].on, false);
    assert.equal(d.mods.right[6].on, true);
    assert.equal(d.mods.right[7].on, true);
});

test("merge over a partial object fills the rest from defaults", () => {
    const merged = H.merge({ barHeight: 36, unit: "f" });
    assert.equal(merged.barHeight, 36);
    assert.equal(merged.unit, "f");
    assert.equal(merged.barRadius, 9);
    assert.equal(merged.accent, "#9ecbeb");
    assert.ok(!("v" in merged));
    assert.ok(!("bogus" in H.merge({ bogus: 1 })));
});

test("merge on null or garbage returns pure defaults", () => {
    assert.deepEqual(H.merge(null), H.defaults());
    assert.deepEqual(H.merge("nope"), H.defaults());
    assert.equal(H.parse("{broken"), null);
    assert.equal(H.parse("42"), null);
});

test("merge clamps and snaps numeric ranges", () => {
    assert.equal(H.merge({ barHeight: 99 }).barHeight, 44);
    assert.equal(H.merge({ barHeight: 10 }).barHeight, 24);
    assert.equal(H.merge({ barHeight: 30.6 }).barHeight, 31);
    assert.equal(H.merge({ barHeight: "30" }).barHeight, 30);
    assert.equal(H.merge({ gap: 1 }).gap, 4);
    assert.equal(H.merge({ barRadius: -3 }).barRadius, 0);
    assert.equal(H.merge({ warmth: 3333 }).warmth, 3350);
    assert.equal(H.merge({ warmth: 100 }).warmth, 1900);
    assert.equal(H.merge({ warmth: NaN }).warmth, 3400);
});

test("merge falls back on invalid enums, colors and names", () => {
    assert.equal(H.merge({ font: "comic-sans" }).font, "oppo");
    assert.equal(H.merge({ position: "left" }).position, "top");
    assert.equal(H.merge({ pollMax: 120 }).pollMax, 300);
    assert.equal(H.merge({ accent: "red" }).accent, "#9ecbeb");
    assert.equal(H.merge({ accent: "#a992e0" }).accent, "#a992e0");
    assert.equal(H.merge({ wall: "../../etc/passwd" }).wall, H.defaults().wall);
    assert.equal(H.merge({ wall: "" }).wall, H.defaults().wall);
    assert.equal(H.merge({ monitor: "eDP-1" }).monitor, "eDP-1");
    assert.equal(H.merge({ wallAccent: "blue" }).wallAccent, "");
});

test("normalizeMods drops unknown ids and dedupes across columns", () => {
    const next = H.normalizeMods({
        left: [{ id: "clock", on: true }, { id: "flux", on: true }, { id: "clock", on: false }],
        center: [{ id: "clock", on: false }],
        right: []
    });
    assert.deepEqual(next.left.map(m => m.id), ["clock", "ws", "media"],
        "flux dropped, duplicate clock collapsed, absent defaults appended");
    assert.equal(next.left[0].on, true, "first occurrence of a duplicate wins");
    assert.deepEqual(next.center.map(m => m.id), ["weather"]);
    const all = [...next.left, ...next.center, ...next.right].map(m => m.id).sort();
    assert.deepEqual(all, [...H.MODULE_IDS].sort());
});

test("normalizeMods appends ids missing from the file at their default column", () => {
    const next = H.normalizeMods({ left: [{ id: "vol", on: false }], center: [], right: [] });
    assert.deepEqual(next.left.map(m => m.id), ["vol", "ws", "media"]);
    assert.equal(next.left[0].on, false);
    assert.deepEqual(next.center.map(m => m.id), ["clock", "weather"]);
    assert.deepEqual(next.right.map(m => m.id),
        ["t3", "wifi", "batt", "bell", "bt", "idle", "control"]);
    assert.ok(next.left.some(m => m.id === "media" && m.on === false),
        "appended module keeps its default enable flag");
});

test("normalizeMods falls back to the default flag for a non-boolean", () => {
    const next = H.normalizeMods({ left: [{ id: "media", on: "yes" }], center: [], right: [] });
    assert.equal(next.left[0].on, false);
});

test("Idle inhibit and Control Center persist in any module column", () => {
    const raw = H.defaultMods();
    raw.right = raw.right.filter(m => m.id !== "idle" && m.id !== "control");
    raw.left.unshift({ id: "control", on: true });
    raw.center.push({ id: "idle", on: true });

    const next = H.normalizeMods(raw);
    assert.equal(next.left[0].id, "control");
    assert.equal(next.center.at(-1).id, "idle");
    assert.ok(!next.right.some(m => m.id === "idle" || m.id === "control"));
});

test("serialize is stable, versioned, and round-trips through merge", () => {
    const d = H.defaults();
    const text = H.serialize(d);
    assert.match(text, /^\{\n  "v": 1,\n  "wall":/);
    assert.ok(text.endsWith("\n"));
    const reparsed = H.merge(H.parse(text));
    assert.equal(H.serialize(reparsed), text);
});
