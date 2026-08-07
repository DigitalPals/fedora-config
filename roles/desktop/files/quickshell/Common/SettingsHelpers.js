// Pure settings-schema helpers shared by QML and Node tests.
// Keep this file free of Qt APIs so persistence stays deterministic.

var VERSION = 3;

var MODULE_IDS = [
    "ws", "media", "clock", "weather", "t3", "usage", "vol", "wifi", "batt", "bell",
    "bt", "idle", "control"
];

var DETAIL_IDS = ["media", "weather", "clock", "t3", "vol", "batt", "usage"];
var DETAIL_POLICIES = ["auto", "prefer", "compact"];

var FONT_CHOICES = [
    { id: "oppo", label: "OPPO Sans 4.0", family: "OPPO Sans 4.0" },
    { id: "plex", label: "IBM Plex Sans", family: "IBM Plex Sans" },
    { id: "mono", label: "JetBrains Mono", family: "JetBrains Mono" }
];

function defaultMods() {
    function mod(id, on) {
        return { id: id, on: on, detail: "auto" };
    }
    return {
        left: [mod("ws", true), mod("media", false)],
        center: [mod("clock", true), mod("weather", true)],
        right: [
            mod("t3", true), mod("usage", true), mod("vol", true),
            mod("wifi", true), mod("batt", true), mod("bell", true),
            mod("bt", false), mod("idle", true), mod("control", true)
        ]
    };
}

// Per-module options: one object per configurable module id. Modules absent
// here (wifi, bt, idle, control) have no options and get no settings cog.
function defaultModOpts() {
    return {
        ws: { minSlots: 5, hideEmpty: false, style: "numbers" },
        media: { titleFormat: "title-artist", maxWidth: 220 },
        clock: { seconds: false, showDate: true, dateFormat: "ddd dd" },
        weather: { place: "Emmen", lat: 52.78, lon: 6.9, pollMins: 20 },
        t3: { showLabel: true, pulse: true },
        usage: { claude: true, codex: true, kimi: true, warnAt: 25, critAt: 10 },
        vol: { step: 5, showPct: true, middleClick: "mute" },
        batt: { showPct: true, warnAt: 20, critAt: 10 },
        bell: { badge: "dot" }
    };
}

function defaults() {
    return {
        wall: "snow-capped-mountains-with-full-moon-lo.jpg",
        wallDir: "~/Pictures/Wallpapers",
        shuffle: "Off",
        barHeight: 30,
        barRadius: 9,
        font: "oppo",
        accent: "#9ecbeb",
        accentWall: false,
        position: "top",
        floating: true,
        gap: 8,
        autoHide: false,
        exclusive: true,
        monitor: "All",
        clock24: true,
        unit: "c",
        warmth: 3400,
        osd: "top",
        pollMax: 300,
        scrollFactor: 1.0,
        notifDnd: false,
        notifQuiet: "off",
        notifQuietStart: 1320,
        notifQuietEnd: 420,
        notifDuration: 8,
        notifPosition: "top-right",
        notifDensity: "default",
        notifIcons: true,
        notifProgress: true,
        notifBodyLines: 2,
        mods: defaultMods(),
        modOpts: defaultModOpts(),
        wallAccent: "",
        wallAccentFor: ""
    };
}

function intIn(value, min, max, step, fallback) {
    if (typeof value !== "number" || !isFinite(value))
        return fallback;
    var snapped = step > 1 ? Math.round(value / step) * step : Math.round(value);
    return Math.min(max, Math.max(min, snapped));
}

function realIn(value, min, max, step, fallback) {
    if (typeof value !== "number" || !isFinite(value))
        return fallback;
    var snapped = Math.round(value / step) * step;
    return Math.min(max, Math.max(min, Number(snapped.toFixed(6))));
}

function enumIn(value, options, fallback) {
    return options.indexOf(value) !== -1 ? value : fallback;
}

function boolIn(value, fallback) {
    return typeof value === "boolean" ? value : fallback;
}

function textIn(value, maxLen, fallback) {
    if (typeof value !== "string")
        return fallback;
    if (value.indexOf("\0") !== -1 || value.indexOf("\n") !== -1 || value.indexOf("\r") !== -1)
        return fallback;
    var trimmed = value.trim();
    return trimmed !== "" && trimmed.length <= maxLen ? trimmed : fallback;
}

function hexIn(value, fallback) {
    return typeof value === "string" && /^#[0-9a-fA-F]{6}$/.test(value) ? value : fallback;
}

function nameIn(value, fallback) {
    return typeof value === "string" && value !== "" && value.indexOf("/") === -1
        ? value : fallback;
}

function pathIn(value, fallback) {
    if (typeof value !== "string" || value === "" || value.indexOf("\0") !== -1
            || value.indexOf("\n") !== -1 || value.indexOf("\r") !== -1)
        return fallback;
    if (value[0] === "/")
        return value.replace(/\/{2,}/g, "/").replace(/\/$/, "") || "/";
    if (value === "~" || value.indexOf("~/") === 0) {
        var tail = value === "~" ? "" : value.slice(2);
        if (tail.split("/").some(function(part) { return part === ".."; }))
            return fallback;
        return tail === "" ? "~" : "~/" + tail.replace(/\/{2,}/g, "/").replace(/\/$/, "");
    }
    return fallback;
}

function detailIn(value) {
    return enumIn(value, DETAIL_POLICIES, "auto");
}

// Sanitize a persisted module layout: known ids only, first occurrence wins,
// ids a newer schema knows about but the file does not are appended at their
// default column's end so shipping a new module never requires migration.
function normalizeMods(raw) {
    var base = defaultMods();
    if (!raw || typeof raw !== "object")
        return base;
    var defaultOn = {};
    var defaultCol = {};
    ["left", "center", "right"].forEach(function(col) {
        base[col].forEach(function(entry) {
            defaultOn[entry.id] = entry.on;
            defaultCol[entry.id] = col;
        });
    });
    var seen = {};
    var next = { left: [], center: [], right: [] };
    ["left", "center", "right"].forEach(function(col) {
        var list = Array.isArray(raw[col]) ? raw[col] : [];
        list.forEach(function(entry) {
            var id = entry ? entry.id : undefined;
            if (MODULE_IDS.indexOf(id) === -1 || seen[id])
                return;
            seen[id] = true;
            next[col].push({
                id: id,
                on: typeof entry.on === "boolean" ? entry.on : defaultOn[id],
                detail: detailIn(entry.detail)
            });
        });
    });
    MODULE_IDS.forEach(function(id) {
        if (!seen[id])
            next[defaultCol[id]].push({ id: id, on: defaultOn[id], detail: "auto" });
    });
    return next;
}

// Per-key validators for module options. Shared by normalizeModOpts and any
// UI that needs a key's bounds; fallback comes from defaultModOpts.
var MOD_OPT_CHECKS = {
    ws: {
        minSlots: function(v, d) { return intIn(v, 1, 10, 1, d); },
        hideEmpty: boolIn,
        style: function(v, d) { return enumIn(v, ["numbers", "dots"], d); }
    },
    media: {
        titleFormat: function(v, d) {
            return enumIn(v, ["title-artist", "title", "artist-title"], d);
        },
        maxWidth: function(v, d) { return intIn(v, 120, 360, 20, d); }
    },
    clock: {
        seconds: boolIn,
        showDate: boolIn,
        dateFormat: function(v, d) {
            return enumIn(v, ["ddd dd", "ddd d MMM", "dd MMM", "dd-MM"], d);
        }
    },
    weather: {
        place: function(v, d) { return textIn(v, 40, d); },
        lat: function(v, d) { return realIn(v, -90, 90, 0.0001, d); },
        lon: function(v, d) { return realIn(v, -180, 180, 0.0001, d); },
        pollMins: function(v, d) { return intIn(v, 5, 60, 5, d); }
    },
    t3: { showLabel: boolIn, pulse: boolIn },
    usage: {
        claude: boolIn,
        codex: boolIn,
        kimi: boolIn,
        warnAt: function(v, d) { return intIn(v, 10, 50, 5, d); },
        critAt: function(v, d) { return intIn(v, 5, 25, 5, d); }
    },
    vol: {
        step: function(v, d) { return intIn(v, 1, 10, 1, d); },
        showPct: boolIn,
        middleClick: function(v, d) { return enumIn(v, ["mute", "none"], d); }
    },
    batt: {
        showPct: boolIn,
        warnAt: function(v, d) { return intIn(v, 10, 40, 5, d); },
        critAt: function(v, d) { return intIn(v, 5, 20, 5, d); }
    },
    bell: {
        badge: function(v, d) { return enumIn(v, ["dot", "count", "off"], d); }
    }
};

// Sanitize persisted module options: known modules and keys only, each value
// through its validator; anything unknown or invalid falls back to defaults.
function normalizeModOpts(raw) {
    var next = defaultModOpts();
    if (!raw || typeof raw !== "object")
        return next;
    Object.keys(MOD_OPT_CHECKS).forEach(function(id) {
        var entry = raw[id];
        if (!entry || typeof entry !== "object")
            return;
        Object.keys(MOD_OPT_CHECKS[id]).forEach(function(key) {
            if (key in entry)
                next[id][key] = MOD_OPT_CHECKS[id][key](entry[key], next[id][key]);
        });
    });
    return next;
}

// Schema 1 exposed T3 Code and model usage as one `t3` module. Preserve that
// composite module's placement and visibility when loading an older layout by
// inserting the new `usage` entry directly after it. Current-schema layouts
// continue through normal normalization, where missing ids use their defaults.
function migrateMods(raw, sourceVersion) {
    if ((sourceVersion !== undefined && sourceVersion !== 1)
            || !raw || typeof raw !== "object")
        return normalizeMods(raw);

    var migrated = { left: [], center: [], right: [] };
    var usagePresent = false;
    ["left", "center", "right"].forEach(function(col) {
        var list = Array.isArray(raw[col]) ? raw[col] : [];
        migrated[col] = list.map(function(entry) {
            return entry && typeof entry === "object"
                ? { id: entry.id, on: entry.on, detail: entry.detail }
                : entry;
        });
        if (list.some(function(entry) { return entry && entry.id === "usage"; }))
            usagePresent = true;
    });

    if (!usagePresent) {
        for (var i = 0; i < 3; i++) {
            var col = ["left", "center", "right"][i];
            var t3Index = migrated[col].findIndex(function(entry) {
                return entry && entry.id === "t3";
            });
            if (t3Index === -1)
                continue;
            var t3 = migrated[col][t3Index];
            migrated[col].splice(t3Index + 1, 0, {
                id: "usage",
                on: typeof t3.on === "boolean" ? t3.on : true,
                detail: "auto"
            });
            break;
        }
    }
    return normalizeMods(migrated);
}

function merge(parsed) {
    var d = defaults();
    if (!parsed || typeof parsed !== "object")
        return d;
    return {
        wall: nameIn(parsed.wall, d.wall),
        wallDir: pathIn(parsed.wallDir, d.wallDir),
        shuffle: enumIn(parsed.shuffle, ["Off", "15m", "1h", "1d"], d.shuffle),
        barHeight: intIn(parsed.barHeight, 24, 44, 1, d.barHeight),
        barRadius: intIn(parsed.barRadius, 0, 16, 1, d.barRadius),
        font: enumIn(parsed.font, ["oppo", "plex", "mono"], d.font),
        accent: hexIn(parsed.accent, d.accent),
        accentWall: boolIn(parsed.accentWall, d.accentWall),
        position: enumIn(parsed.position, ["top", "bottom"], d.position),
        floating: boolIn(parsed.floating, d.floating),
        gap: intIn(parsed.gap, 4, 20, 1, d.gap),
        autoHide: boolIn(parsed.autoHide, d.autoHide),
        exclusive: boolIn(parsed.exclusive, d.exclusive),
        monitor: nameIn(parsed.monitor, d.monitor),
        clock24: boolIn(parsed.clock24, d.clock24),
        unit: enumIn(parsed.unit, ["c", "f"], d.unit),
        warmth: intIn(parsed.warmth, 1900, 4500, 50, d.warmth),
        osd: enumIn(parsed.osd, ["top", "bottom"], d.osd),
        pollMax: enumIn(parsed.pollMax, [60, 300, 600], d.pollMax),
        scrollFactor: realIn(parsed.scrollFactor, 0.2, 2.0, 0.1, d.scrollFactor),
        notifDnd: boolIn(parsed.notifDnd, d.notifDnd),
        notifQuiet: enumIn(parsed.notifQuiet, ["off", "nights", "custom"], d.notifQuiet),
        notifQuietStart: intIn(parsed.notifQuietStart, 0, 1425, 15, d.notifQuietStart),
        notifQuietEnd: intIn(parsed.notifQuietEnd, 0, 1425, 15, d.notifQuietEnd),
        notifDuration: intIn(parsed.notifDuration, 4, 20, 1, d.notifDuration),
        notifPosition: enumIn(parsed.notifPosition,
            ["top-left", "top-right", "bottom-left", "bottom-right"], d.notifPosition),
        notifDensity: enumIn(parsed.notifDensity,
            ["compact", "default", "roomy"], d.notifDensity),
        notifIcons: boolIn(parsed.notifIcons, d.notifIcons),
        notifProgress: boolIn(parsed.notifProgress, d.notifProgress),
        notifBodyLines: intIn(parsed.notifBodyLines, 0, 3, 1, d.notifBodyLines),
        mods: migrateMods(parsed.mods, parsed.v),
        modOpts: normalizeModOpts(parsed.modOpts),
        wallAccent: hexIn(parsed.wallAccent, ""),
        wallAccentFor: typeof parsed.wallAccentFor === "string" ? parsed.wallAccentFor : ""
    };
}

// Quiet hours. "nights" is a fixed preset; "custom" uses the stored
// minutes-since-midnight bounds. A range crossing midnight wraps.
var QUIET_NIGHTS = { start: 1320, end: 420 };

function quietRange(quiet, start, end) {
    if (quiet === "nights")
        return { start: QUIET_NIGHTS.start, end: QUIET_NIGHTS.end };
    if (quiet === "custom")
        return { start: start, end: end };
    return null;
}

function quietActive(quiet, start, end, minutesNow) {
    var range = quietRange(quiet, start, end);
    if (!range || range.start === range.end)
        return false;
    if (range.start < range.end)
        return minutesNow >= range.start && minutesNow < range.end;
    return minutesNow >= range.start || minutesNow < range.end;
}

function formatMinutes(total) {
    var h = Math.floor(total / 60) % 24;
    var m = total % 60;
    return String(h).padStart(2, "0") + ":" + String(m).padStart(2, "0");
}

function hueToHex(degrees) {
    var h = ((Number(degrees) % 360) + 360) % 360 / 360;
    var s = 0.50;
    var l = 0.75;
    function hueChannel(p, q, t) {
        if (t < 0) t += 1;
        if (t > 1) t -= 1;
        if (t < 1 / 6) return p + (q - p) * 6 * t;
        if (t < 1 / 2) return q;
        if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
        return p;
    }
    var q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    var p = 2 * l - q;
    var channels = [hueChannel(p, q, h + 1 / 3), hueChannel(p, q, h), hueChannel(p, q, h - 1 / 3)];
    return "#" + channels.map(function(channel) {
        return Math.round(channel * 255).toString(16).padStart(2, "0");
    }).join("");
}

function hexHue(value, fallback) {
    if (typeof value !== "string" || !/^#[0-9a-fA-F]{6}$/.test(value))
        return fallback === undefined ? 0 : fallback;
    var r = parseInt(value.slice(1, 3), 16) / 255;
    var g = parseInt(value.slice(3, 5), 16) / 255;
    var b = parseInt(value.slice(5, 7), 16) / 255;
    var max = Math.max(r, g, b);
    var min = Math.min(r, g, b);
    if (max === min)
        return fallback === undefined ? 0 : fallback;
    var d = max - min;
    var h = max === r ? ((g - b) / d + (g < b ? 6 : 0))
        : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
    return Math.round(h * 60) % 360;
}

function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

function restoreSnapshot(current, snapshot) {
    var restored = clone(current);
    Object.keys(snapshot || {}).forEach(function(key) {
        restored[key] = clone(snapshot[key]);
    });
    return restored;
}

// Deterministic serialization: fixed key order so snapshot equality can be
// compared as strings (self-write echo detection) and diffs stay readable.
function serialize(settings) {
    var ordered = { v: VERSION };
    Object.keys(defaults()).forEach(function(key) {
        ordered[key] = settings[key];
    });
    return JSON.stringify(ordered, null, 2) + "\n";
}

function parse(text) {
    try {
        var parsed = JSON.parse(text);
        return parsed && typeof parsed === "object" ? parsed : null;
    } catch (e) {
        return null;
    }
}

var exported = {
    MODULE_IDS: MODULE_IDS,
    DETAIL_IDS: DETAIL_IDS,
    DETAIL_POLICIES: DETAIL_POLICIES,
    FONT_CHOICES: FONT_CHOICES,
    defaults: defaults,
    defaultMods: defaultMods,
    defaultModOpts: defaultModOpts,
    normalizeMods: normalizeMods,
    normalizeModOpts: normalizeModOpts,
    migrateMods: migrateMods,
    pathIn: pathIn,
    detailIn: detailIn,
    quietRange: quietRange,
    quietActive: quietActive,
    formatMinutes: formatMinutes,
    hueToHex: hueToHex,
    hexHue: hexHue,
    clone: clone,
    restoreSnapshot: restoreSnapshot,
    merge: merge,
    serialize: serialize,
    parse: parse
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
