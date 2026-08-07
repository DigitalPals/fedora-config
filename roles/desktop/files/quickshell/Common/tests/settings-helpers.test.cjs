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
    assert.equal(d.scrollFactor, 1.0);
    assert.equal(d.shuffle, "Off");
    assert.equal(d.wallDir, "~/Pictures/Wallpapers");
    assert.equal(d.notifDnd, false);
    assert.equal(d.notifQuiet, "off");
    assert.equal(d.notifQuietStart, 1320);
    assert.equal(d.notifQuietEnd, 420);
    assert.equal(d.notifDuration, 8);
    assert.equal(d.notifPosition, "top-right");
    assert.equal(d.notifDensity, "default");
    assert.equal(d.notifIcons, true);
    assert.equal(d.notifProgress, true);
    assert.equal(d.notifBodyLines, 2);
    assert.deepEqual(d.mods.left.map(m => m.id), ["ws", "media"]);
    assert.deepEqual(d.mods.center.map(m => m.id), ["clock", "weather"]);
    assert.deepEqual(d.mods.right.map(m => m.id),
        ["t3", "usage", "vol", "wifi", "batt", "bell", "bt", "idle", "control"]);
    assert.equal(d.mods.left[1].on, false);
    assert.equal(d.mods.right[6].on, false);
    assert.equal(d.mods.right[7].on, true);
    assert.equal(d.mods.right[8].on, true);
    assert.ok([...d.mods.left, ...d.mods.center, ...d.mods.right]
        .every(module => module.detail === "auto"));
    assert.deepEqual(Object.keys(d.modOpts),
        ["ws", "media", "clock", "weather", "t3", "usage", "vol", "batt", "bell"]);
    assert.equal(d.modOpts.ws.minSlots, 5);
    assert.equal(d.modOpts.media.maxWidth, 220);
    assert.equal(d.modOpts.clock.seconds, false);
    assert.equal(d.modOpts.clock.dateFormat, "ddd dd");
    assert.deepEqual(d.modOpts.weather,
        { place: "Emmen", lat: 52.78, lon: 6.9, pollMins: 20 });
    assert.equal(d.modOpts.usage.warnAt, 25);
    assert.equal(d.modOpts.usage.critAt, 10);
    assert.equal(d.modOpts.vol.step, 5);
    assert.equal(d.modOpts.vol.middleClick, "mute");
    assert.deepEqual(d.modOpts.batt, { showPct: true, warnAt: 20, critAt: 10 });
    assert.equal(d.modOpts.bell.badge, "dot");
});

test("normalizeModOpts drops unknown modules and keys", () => {
    const next = H.normalizeModOpts({
        flux: { on: true },
        wifi: { anything: 1 },
        clock: { seconds: true, bogus: "x" },
        vol: "not-an-object"
    });
    assert.ok(!("flux" in next) && !("wifi" in next));
    assert.equal(next.clock.seconds, true);
    assert.ok(!("bogus" in next.clock));
    assert.deepEqual(next.vol, H.defaultModOpts().vol);
    assert.deepEqual(H.normalizeModOpts(null), H.defaultModOpts());
    assert.deepEqual(H.normalizeModOpts("nope"), H.defaultModOpts());
});

test("normalizeModOpts clamps, snaps, and validates option values", () => {
    const next = H.normalizeModOpts({
        ws: { minSlots: 99, style: "triangles" },
        media: { maxWidth: 133, titleFormat: "title" },
        weather: { lat: 200, lon: -12.34567, place: "  Emmen Centrum  ", pollMins: 7 },
        usage: { warnAt: 8, critAt: 60, claude: "yes" },
        vol: { step: 0, middleClick: "detonate" },
        batt: { warnAt: 33, critAt: 3 },
        bell: { badge: "count" }
    });
    assert.equal(next.ws.minSlots, 10);
    assert.equal(next.ws.style, "numbers");
    assert.equal(next.media.maxWidth, 140);
    assert.equal(next.media.titleFormat, "title");
    assert.equal(next.weather.lat, 90, "out-of-range latitude clamps like other numerics");
    assert.equal(next.weather.lon, -12.3457);
    assert.equal(next.weather.place, "Emmen Centrum");
    assert.equal(next.weather.pollMins, 5);
    assert.equal(next.usage.warnAt, 10);
    assert.equal(next.usage.critAt, 25);
    assert.equal(next.usage.claude, true, "non-boolean falls back to default");
    assert.equal(next.vol.step, 1);
    assert.equal(next.vol.middleClick, "mute");
    assert.equal(next.batt.warnAt, 35, "snaps to step 5");
    assert.equal(next.batt.critAt, 5);
    assert.equal(next.bell.badge, "count");
});

test("weather place rejects control characters and oversized strings", () => {
    const d = H.defaultModOpts().weather.place;
    assert.equal(H.normalizeModOpts({ weather: { place: "a\nb" } }).weather.place, d);
    assert.equal(H.normalizeModOpts({ weather: { place: "a\0b" } }).weather.place, d);
    assert.equal(H.normalizeModOpts({ weather: { place: "   " } }).weather.place, d);
    assert.equal(H.normalizeModOpts({ weather: { place: "x".repeat(41) } }).weather.place, d);
    assert.equal(H.normalizeModOpts({ weather: { place: "x".repeat(40) } }).weather.place,
        "x".repeat(40));
});

test("merge fills a missing modOpts from defaults and sanitizes a partial one", () => {
    assert.deepEqual(H.merge({ barHeight: 36 }).modOpts, H.defaultModOpts());
    const merged = H.merge({ modOpts: { batt: { showPct: false } } });
    assert.equal(merged.modOpts.batt.showPct, false);
    assert.equal(merged.modOpts.batt.warnAt, 20);
    assert.deepEqual(merged.modOpts.clock, H.defaultModOpts().clock);
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
    assert.equal(H.merge({ scrollFactor: 1.26 }).scrollFactor, 1.3);
    assert.equal(H.merge({ scrollFactor: 0.01 }).scrollFactor, 0.2);
    assert.equal(H.merge({ scrollFactor: 4 }).scrollFactor, 2.0);
    assert.equal(H.merge({ scrollFactor: "1.5" }).scrollFactor, 1.0);
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
        ["t3", "usage", "wifi", "batt", "bell", "bt", "idle", "control"]);
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

test("version one layouts insert usage after t3 with its column and enabled state", () => {
    const enabled = H.merge({
        v: 1,
        mods: {
            left: [{ id: "ws", on: true }],
            center: [{ id: "t3", on: true }, { id: "clock", on: true }],
            right: [{ id: "vol", on: true }]
        }
    }).mods;
    assert.deepEqual(enabled.center.slice(0, 3), [
        { id: "t3", on: true, detail: "auto" },
        { id: "usage", on: true, detail: "auto" },
        { id: "clock", on: true, detail: "auto" }
    ]);

    const disabled = H.merge({
        v: 1,
        mods: {
            left: [],
            center: [],
            right: [{ id: "vol", on: true }, { id: "t3", on: false }]
        }
    }).mods;
    assert.deepEqual(disabled.right.slice(0, 3), [
        { id: "vol", on: true, detail: "auto" },
        { id: "t3", on: false, detail: "auto" },
        { id: "usage", on: false, detail: "auto" }
    ]);
});

test("unversioned layouts receive the same composite t3 migration", () => {
    const mods = H.merge({
        mods: {
            left: [{ id: "t3", on: false }, { id: "media", on: true }],
            center: [],
            right: []
        }
    }).mods;
    assert.deepEqual(mods.left.slice(0, 3), [
        { id: "t3", on: false, detail: "auto" },
        { id: "usage", on: false, detail: "auto" },
        { id: "media", on: true, detail: "auto" }
    ]);
});

test("version two normalization preserves usage independently and uniquely", () => {
    const mods = H.merge({
        v: 2,
        mods: {
            left: [{ id: "usage", on: false }, { id: "usage", on: true }],
            center: [{ id: "t3", on: true }],
            right: []
        }
    }).mods;
    assert.deepEqual(mods.left.slice(0, 1), [{ id: "usage", on: false, detail: "auto" }]);
    assert.deepEqual(mods.center.slice(0, 1), [{ id: "t3", on: true, detail: "auto" }]);
    assert.equal([...mods.left, ...mods.center, ...mods.right]
        .filter(m => m.id === "usage").length, 1);
});

test("serialize is stable, versioned, and round-trips through merge", () => {
    const d = H.defaults();
    const text = H.serialize(d);
    assert.match(text, /^\{\n  "v": 3,\n  "wall":/);
    assert.ok(text.endsWith("\n"));
    const reparsed = H.merge(H.parse(text));
    assert.equal(H.serialize(reparsed), text);
});

test("v1 and v2 layouts migrate to v3 detail policies without losing placement", () => {
    for (const v of [1, 2]) {
        const merged = H.merge({
            v,
            mods: {
                left: [{ id: "weather", on: false }],
                center: [{ id: "clock", on: true }],
                right: [{ id: "t3", on: true }, ...(v === 2 ? [{ id: "usage", on: false }] : [])]
            }
        });
        assert.equal(merged.mods.left[0].id, "weather");
        assert.equal(merged.mods.left[0].on, false);
        assert.ok([...merged.mods.left, ...merged.mods.center, ...merged.mods.right]
            .every(module => module.detail === "auto"));
    }
});

test("wallpaper paths and module detail policies are validated", () => {
    assert.equal(H.merge({ wallDir: "/mnt/Wall papers" }).wallDir, "/mnt/Wall papers");
    assert.equal(H.merge({ wallDir: "~/Pictures/Other" }).wallDir, "~/Pictures/Other");
    assert.equal(H.merge({ wallDir: "relative/path" }).wallDir, H.defaults().wallDir);
    assert.equal(H.merge({ wallDir: "~/Pictures/../Secrets" }).wallDir, H.defaults().wallDir);
    const mods = H.normalizeMods({ left: [
        { id: "media", on: true, detail: "prefer" },
        { id: "clock", on: true, detail: "invalid" }
    ]});
    assert.equal(mods.left[0].detail, "prefer");
    assert.equal(mods.left[1].detail, "auto");
});

test("notification settings are validated, clamped, and snapped", () => {
    assert.equal(H.merge({ notifDnd: "yes" }).notifDnd, false);
    assert.equal(H.merge({ notifQuiet: "sometimes" }).notifQuiet, "off");
    assert.equal(H.merge({ notifQuiet: "nights" }).notifQuiet, "nights");
    assert.equal(H.merge({ notifQuietStart: 1322 }).notifQuietStart, 1320);
    assert.equal(H.merge({ notifQuietStart: -10 }).notifQuietStart, 0);
    assert.equal(H.merge({ notifQuietEnd: 9999 }).notifQuietEnd, 1425);
    assert.equal(H.merge({ notifDuration: 1 }).notifDuration, 4);
    assert.equal(H.merge({ notifDuration: 99 }).notifDuration, 20);
    assert.equal(H.merge({ notifPosition: "middle" }).notifPosition, "top-right");
    assert.equal(H.merge({ notifPosition: "bottom-left" }).notifPosition, "bottom-left");
    assert.equal(H.merge({ notifDensity: "cozy" }).notifDensity, "default");
    assert.equal(H.merge({ notifBodyLines: 7 }).notifBodyLines, 3);
    assert.equal(H.merge({ notifBodyLines: -1 }).notifBodyLines, 0);
});

test("quiet hours resolve presets, wrap midnight, and format as HH:MM", () => {
    assert.equal(H.quietRange("off", 0, 0), null);
    assert.deepEqual(H.quietRange("nights", 600, 700), { start: 1320, end: 420 });
    assert.deepEqual(H.quietRange("custom", 600, 700), { start: 600, end: 700 });

    // Nights: 22:00 – 07:00 wraps midnight.
    assert.equal(H.quietActive("nights", 0, 0, 1320), true);
    assert.equal(H.quietActive("nights", 0, 0, 30), true);
    assert.equal(H.quietActive("nights", 0, 0, 419), true);
    assert.equal(H.quietActive("nights", 0, 0, 420), false);
    assert.equal(H.quietActive("nights", 0, 0, 720), false);
    assert.equal(H.quietActive("off", 0, 1439, 720), false);

    // Custom same-day range, and a degenerate empty range.
    assert.equal(H.quietActive("custom", 540, 1020, 720), true);
    assert.equal(H.quietActive("custom", 540, 1020, 1020), false);
    assert.equal(H.quietActive("custom", 600, 600, 600), false);

    assert.equal(H.formatMinutes(0), "00:00");
    assert.equal(H.formatMinutes(1320), "22:00");
    assert.equal(H.formatMinutes(425), "07:05");
});

test("hue conversion stays pastel and contrasts with accent text", () => {
    function luminance(hex) {
        const channels = [1, 3, 5].map(offset => parseInt(hex.slice(offset, offset + 2), 16) / 255)
            .map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
    }
    const foreground = luminance("#0e0f13");
    for (let hue = 0; hue < 360; hue += 15) {
        const color = H.hueToHex(hue);
        assert.match(color, /^#[0-9a-f]{6}$/);
        assert.ok((luminance(color) + 0.05) / (foreground + 0.05) >= 4.5);
    }
});

test("reset snapshots restore only the covered values", () => {
    const current = { accent: "#ffffff", font: "mono", gap: 20 };
    const snapshot = { accent: "#9ecbeb", font: "oppo" };
    assert.deepEqual(H.restoreSnapshot(current, snapshot), {
        accent: "#9ecbeb", font: "oppo", gap: 20
    });
    assert.deepEqual(snapshot, { accent: "#9ecbeb", font: "oppo" });
});
