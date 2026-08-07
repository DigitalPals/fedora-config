// Pure settings-schema helpers shared by QML and Node tests.
// Keep this file free of Qt APIs so persistence stays deterministic.

var VERSION = 1;

var MODULE_IDS = [
    "ws", "media", "clock", "weather", "t3", "vol", "wifi", "batt", "bell", "bt",
    "idle", "control"
];

var FONT_CHOICES = [
    { id: "oppo", label: "OPPO Sans 4.0", family: "OPPO Sans 4.0" },
    { id: "plex", label: "IBM Plex Sans", family: "IBM Plex Sans" },
    { id: "mono", label: "JetBrains Mono", family: "JetBrains Mono" }
];

function defaultMods() {
    return {
        left: [{ id: "ws", on: true }, { id: "media", on: false }],
        center: [{ id: "clock", on: true }, { id: "weather", on: true }],
        right: [
            { id: "t3", on: true }, { id: "vol", on: true }, { id: "wifi", on: true },
            { id: "batt", on: true }, { id: "bell", on: true }, { id: "bt", on: false },
            { id: "idle", on: true }, { id: "control", on: true }
        ]
    };
}

function defaults() {
    return {
        wall: "snow-capped-mountains-with-full-moon-lo.jpg",
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
        mods: defaultMods(),
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

function enumIn(value, options, fallback) {
    return options.indexOf(value) !== -1 ? value : fallback;
}

function boolIn(value, fallback) {
    return typeof value === "boolean" ? value : fallback;
}

function hexIn(value, fallback) {
    return typeof value === "string" && /^#[0-9a-fA-F]{6}$/.test(value) ? value : fallback;
}

function nameIn(value, fallback) {
    return typeof value === "string" && value !== "" && value.indexOf("/") === -1
        ? value : fallback;
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
            next[col].push({ id: id, on: typeof entry.on === "boolean" ? entry.on : defaultOn[id] });
        });
    });
    MODULE_IDS.forEach(function(id) {
        if (!seen[id])
            next[defaultCol[id]].push({ id: id, on: defaultOn[id] });
    });
    return next;
}

function merge(parsed) {
    var d = defaults();
    if (!parsed || typeof parsed !== "object")
        return d;
    return {
        wall: nameIn(parsed.wall, d.wall),
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
        mods: normalizeMods(parsed.mods),
        wallAccent: hexIn(parsed.wallAccent, ""),
        wallAccentFor: typeof parsed.wallAccentFor === "string" ? parsed.wallAccentFor : ""
    };
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
    FONT_CHOICES: FONT_CHOICES,
    defaults: defaults,
    defaultMods: defaultMods,
    normalizeMods: normalizeMods,
    merge: merge,
    serialize: serialize,
    parse: parse
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
