// Pure settings-schema helpers shared by QML and Node tests.
// Keep this file free of Qt APIs so persistence stays deterministic.

var VERSION = 10;

var BAR_STYLES = ["hug", "floating", "attached"];
var PALETTE_MODES = ["wallpaper", "fixed"];

// Reads in default layout order: left, then center, then right. The order
// only decides where an id the settings file has never seen is appended, but
// keeping the two lists in step is what makes that placement predictable.
//
// Schema 4 (the glass menubar) retired three ids. `bell` folded into the
// centre clock — that button is the notification centre now; `idle` became a
// Control Center toggle whose state shows as a coffee mark inside the clock;
// and `control` became the status pill itself, so a separate trigger for it
// would open the panel the pill already owns.
var MODULE_IDS = [
    "ws", "media", "indicators", "clock", "weather", "updates", "gh", "t3", "usage", "tray",
    "vol", "wifi", "bt", "batt"
];

var RETIRED_MODULE_IDS = ["bell", "idle", "control"];

var DETAIL_IDS = ["media", "weather", "clock", "t3", "usage", "gh", "updates",
    "vol", "batt"];
var DETAIL_POLICIES = ["auto", "prefer", "compact"];

var FONT_CHOICES = [
    { id: "google", label: "Google Sans Flex", family: "Google Sans Flex" },
    { id: "urbanist", label: "Urbanist", family: "Urbanist" },
    { id: "oppo", label: "OPPO Sans 4.0", family: "OPPO Sans 4.0" },
    { id: "plex", label: "IBM Plex Sans", family: "IBM Plex Sans" },
    { id: "mono", label: "JetBrains Mono", family: "JetBrains Mono" }
];

var FONT_IDS = FONT_CHOICES.map(function(choice) { return choice.id; });

// Named menubar colours. `default` and `macos` are adaptive pairs; the
// remaining presets are intentionally fixed so changing the shell theme does
// not silently change a colour the user chose explicitly. Custom is stored as
// HSL components so hue survives even at zero saturation/lightness.
var BAR_COLOR_CHOICES = [
    { id: "default", label: "Shell Default" },
    { id: "macos", label: "macOS" },
    { id: "black", label: "Black" },
    { id: "graphite", label: "Graphite" },
    { id: "slate", label: "Slate" },
    { id: "white", label: "White" },
    { id: "custom", label: "Custom" }
];

var BAR_COLOR_IDS = BAR_COLOR_CHOICES.map(function(choice) { return choice.id; });

var BAR_COLOR_PRESETS = {
    // The original August menubar used this near-black neutral. Keep the
    // adaptive light half, while returning dark mode to the screenshot's
    // quieter surface instead of the later purple-black redesign.
    "default": { dark: "#131419", light: "#ffffff" },
    "macos": { dark: "#1d1d1f", light: "#f5f5f7" },
    "black": { dark: "#000000", light: "#000000" },
    "graphite": { dark: "#2c2c2e", light: "#2c2c2e" },
    "slate": { dark: "#344054", light: "#344054" },
    "white": { dark: "#ffffff", light: "#ffffff" }
};

// How a module draws itself in the bar, which is also how the bar groups a
// run of them. `chip` modules share one rounded background and are separated
// by hairlines; `status` modules are bare glyphs inside the pill that opens
// the Control Center; `solo` modules bring their own pill.
var MODULE_GROUPS = {
    ws: "solo", media: "solo", indicators: "center", clock: "center", weather: "center",
    updates: "solo", gh: "chip", t3: "chip", usage: "chip", tray: "solo",
    vol: "status", wifi: "status", bt: "status", batt: "status"
};

function moduleGroup(id) {
    return MODULE_GROUPS[id] || "solo";
}

function defaultMods() {
    function mod(id, on) {
        return { id: id, on: on, detail: "auto" };
    }
    return {
        left: [mod("ws", true), mod("media", true)],
        center: [mod("indicators", true), mod("clock", true), mod("weather", true)],
        right: [
            mod("updates", true), mod("gh", true), mod("t3", true),
            mod("usage", true), mod("tray", true), mod("vol", true),
            mod("wifi", true), mod("bt", false), mod("batt", true)
        ]
    };
}

// Per-module options: one object per configurable module id. Modules absent
// here (wifi, bt, idle, control) have no options and get no settings cog.
function defaultModOpts() {
    return {
        ws: { minSlots: 5, hideEmpty: false, style: "numbers" },
        media: { titleFormat: "title-artist", maxWidth: 180 },
        indicators: { mode: "hover" },
        clock: { seconds: false, showDate: true, dateFormat: "ddd dd" },
        weather: { place: "Emmen", lat: 52.78, lon: 6.9, pollMins: 20 },
        t3: { showLabel: true },
        usage: { claude: true, codex: true, kimi: true, warnAt: 25, critAt: 10 },
        gh: {
            badge: "dot", repos: 8, pollMins: 5, ciActivity: true,
            toasts: true, watch: []
        },
        updates: { pollMins: 30, flatpak: true, notify: true },
        tray: { expanded: false },
        vol: { step: 5, showPct: true, middleClick: "mute" },
        batt: { showPct: true, warnAt: 20, critAt: 10 }
    };
}

function defaults() {
    return {
        wall: "snow-capped-mountains-with-full-moon-lo.jpg",
        wallDir: "~/Pictures/Wallpapers",
        shuffle: "Off",
        themeMode: "dark",
        glassEnabled: false,
        barColorMode: "default",
        barCustomHue: 230,
        barCustomSaturation: 14,
        barCustomLightness: 9,
        barHeight: 34,
        barRadius: 11,
        font: "google",
        accent: "#9ecbeb",
        paletteMode: "wallpaper",
        position: "top",
        barStyle: "hug",
        gap: 8,
        autoHide: false,
        exclusive: true,
        clock24: true,
        unit: "c",
        warmth: 3400,
        osd: "bottom",
        pollMax: 300,
        scrollFactor: 1.0,
        nightLight: false,
        idleInhibited: true,
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
        modOpts: defaultModOpts()
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

function channelHex(value) {
    return Math.round(Math.min(1, Math.max(0, value)) * 255)
        .toString(16).padStart(2, "0");
}

function hslToHex(hue, saturation, lightness) {
    var h = ((Number(hue) % 360) + 360) % 360 / 360;
    var s = Math.min(100, Math.max(0, Number(saturation))) / 100;
    var l = Math.min(100, Math.max(0, Number(lightness))) / 100;
    if (!isFinite(h) || !isFinite(s) || !isFinite(l))
        return "#000000";

    if (s === 0)
        return "#" + channelHex(l) + channelHex(l) + channelHex(l);

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
    return "#" + [
        hueChannel(p, q, h + 1 / 3),
        hueChannel(p, q, h),
        hueChannel(p, q, h - 1 / 3)
    ].map(channelHex).join("");
}

function resolveBarColor(mode, themeMode, hue, saturation, lightness) {
    var selected = enumIn(mode, BAR_COLOR_IDS, "default");
    if (selected === "custom")
        return hslToHex(hue, saturation, lightness);
    var preset = BAR_COLOR_PRESETS[selected] || BAR_COLOR_PRESETS["default"];
    return themeMode === "light" ? preset.light : preset.dark;
}

function rgbIn(value, fallback) {
    var valid = hexIn(value, fallback || "#000000").toLowerCase();
    return [1, 3, 5].map(function(offset) {
        return parseInt(valid.slice(offset, offset + 2), 16) / 255;
    });
}

function relativeLuminance(value) {
    var linear = rgbIn(value).map(function(channel) {
        return channel <= 0.04045 ? channel / 12.92
            : Math.pow((channel + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
}

function contrastRatio(a, b) {
    var first = relativeLuminance(a);
    var second = relativeLuminance(b);
    return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
}

function mixHex(from, to, amount) {
    var start = rgbIn(from);
    var end = rgbIn(to);
    var t = Math.min(1, Math.max(0, amount));
    return "#" + start.map(function(channel, index) {
        return channelHex(channel + (end[index] - channel) * t);
    }).join("");
}

function foregroundFor(background) {
    return contrastRatio("#ffffff", background) >= contrastRatio("#000000", background)
        ? "#ffffff" : "#000000";
}

// The least foreground mixed over a background that reaches the requested
// contrast. On a mid-luminance colour the hierarchy may collapse to the full
// black/white foreground; readability wins over artificial tonal separation.
function contrastTone(background, foreground, target) {
    if (contrastRatio(foreground, background) < target)
        return foreground;
    var low = 0;
    var high = 1;
    for (var i = 0; i < 16; i++) {
        var mid = (low + high) / 2;
        if (contrastRatio(mixHex(background, foreground, mid), background) >= target)
            high = mid;
        else
            low = mid;
    }
    return mixHex(background, foreground, high);
}

// Preserve a semantic colour when it already reads; otherwise pull it toward
// the bar's automatically selected foreground until it does.
function ensureContrast(value, background, target) {
    var source = hexIn(value, foregroundFor(background)).toLowerCase();
    if (contrastRatio(source, background) >= target)
        return source;
    var foreground = foregroundFor(background);
    var low = 0;
    var high = 1;
    for (var i = 0; i < 16; i++) {
        var mid = (low + high) / 2;
        if (contrastRatio(mixHex(source, foreground, mid), background) >= target)
            high = mid;
        else
            low = mid;
    }
    return mixHex(source, foreground, high);
}

function barPalette(background) {
    var bg = hexIn(background, "#161424").toLowerCase();
    var foreground = foregroundFor(bg);
    return {
        background: bg,
        foreground: foreground,
        textHi: foreground,
        textMid: contrastTone(bg, foreground, 7.0),
        textLow: contrastTone(bg, foreground, 5.5),
        textDim: contrastTone(bg, foreground, 4.8),
        textFaint: contrastTone(bg, foreground, 4.5),
        icon: contrastTone(bg, foreground, 6.0)
    };
}

// Material palettes provide their own on-surface tones. Build the established
// semantic ladder from those roles while retaining the shell-wide AA floor.
function semanticPalette(background, onSurface, onSurfaceVariant) {
    var bg = hexIn(background, "#161424").toLowerCase();
    var hi = ensureContrast(onSurface, bg, 7.0);
    var variant = ensureContrast(onSurfaceVariant, bg, 4.5);
    return {
        background: bg,
        foreground: hi,
        textHi: hi,
        textMid: ensureContrast(variant, bg, 7.0),
        textLow: ensureContrast(variant, bg, 5.5),
        textDim: ensureContrast(variant, bg, 4.8),
        textFaint: ensureContrast(variant, bg, 4.5),
        icon: ensureContrast(variant, bg, 6.0)
    };
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

// The GitHub module's watch list, as *storage*: canonical "owner/repo" only,
// deduped case-insensitively (GitHub resolves names that way, and both
// spellings in the list would poll the same repository twice), capped so a
// hand-edited file cannot turn one poll into hundreds of API calls.
//
// Deliberately stricter and simpler than GitHubHelpers.repoSlug, which also
// accepts a pasted browser URL or an SSH remote. Canonicalising a paste is the
// settings row's job, at the point of entry; by the time a value reaches this
// store it is already a slug, and anything else came from a hand edit.
var MAX_WATCHED_REPOS = 20;
var REPO_SLUG = /^[A-Za-z0-9][A-Za-z0-9-]*\/[A-Za-z0-9._-]+$/;

function repoListIn(value, fallback) {
    if (!Array.isArray(value))
        return fallback;
    var out = [];
    var seen = {};
    for (var i = 0; i < value.length && out.length < MAX_WATCHED_REPOS; i++) {
        if (typeof value[i] !== "string")
            continue;
        var slug = value[i].trim();
        if (slug.length > 120 || !REPO_SLUG.test(slug)
                || slug.split("/")[1] === "." || slug.split("/")[1] === "..")
            continue;
        var key = slug.toLowerCase();
        if (seen[key])
            continue;
        seen[key] = true;
        out.push(slug);
    }
    return out;
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
    indicators: {
        mode: function(v, d) { return enumIn(v, ["hover", "always"], d); }
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
    t3: { showLabel: boolIn },
    usage: {
        claude: boolIn,
        codex: boolIn,
        kimi: boolIn,
        warnAt: function(v, d) { return intIn(v, 10, 50, 5, d); },
        critAt: function(v, d) { return intIn(v, 5, 25, 5, d); }
    },
    gh: {
        badge: function(v, d) { return enumIn(v, ["dot", "count", "off"], d); },
        repos: function(v, d) { return intIn(v, 3, 15, 1, d); },
        pollMins: function(v, d) { return intIn(v, 1, 30, 1, d); },
        ciActivity: boolIn,
        toasts: boolIn,
        watch: repoListIn
    },
    updates: {
        pollMins: function(v, d) { return intIn(v, 10, 240, 10, d); },
        flatpak: boolIn,
        notify: boolIn
    },
    tray: { expanded: boolIn },
    vol: {
        step: function(v, d) { return intIn(v, 1, 10, 1, d); },
        showPct: boolIn,
        middleClick: function(v, d) { return enumIn(v, ["mute", "none"], d); }
    },
    batt: {
        showPct: boolIn,
        warnAt: function(v, d) { return intIn(v, 10, 40, 5, d); },
        critAt: function(v, d) { return intIn(v, 5, 20, 5, d); }
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
    if (!raw || typeof raw !== "object")
        return normalizeMods(raw);

    var migrated = { left: [], center: [], right: [] };
    ["left", "center", "right"].forEach(function(col) {
        var list = Array.isArray(raw[col]) ? raw[col] : [];
        migrated[col] = list.map(function(entry) {
            return entry && typeof entry === "object"
                ? { id: entry.id, on: entry.on, detail: entry.detail }
                : entry;
        });
    });

    // Schema 1 split model usage out of T3 Code. Keep that historical
    // placement migration before applying newer additions.
    var usagePresent = ["left", "center", "right"].some(function(col) {
        return migrated[col].some(function(entry) { return entry && entry.id === "usage"; });
    });
    if ((sourceVersion === undefined || sourceVersion === 1) && !usagePresent) {
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

    // Schema 8 adds quick actions beside the clock. Older layouts retain
    // every user-chosen column, order, visibility, and detail policy; the one
    // new entry is inserted immediately before wherever their clock lives.
    var indicatorsPresent = ["left", "center", "right"].some(function(col) {
        return migrated[col].some(function(entry) {
            return entry && entry.id === "indicators";
        });
    });
    if ((typeof sourceVersion !== "number" || sourceVersion < 8)
            && !indicatorsPresent) {
        for (var j = 0; j < 3; j++) {
            var clockCol = ["left", "center", "right"][j];
            var clockIndex = migrated[clockCol].findIndex(function(entry) {
                return entry && entry.id === "clock";
            });
            if (clockIndex === -1)
                continue;
            migrated[clockCol].splice(clockIndex, 0, {
                id: "indicators", on: true, detail: "auto"
            });
            break;
        }
    }
    return normalizeMods(migrated);
}

// Schema 4 is the glass menubar: a taller bar, full-radius corners, a wider
// floating gap and the design's accent. A settings file written by schema 3
// carries the old geometry for every one of those keys, so loading it as-is
// would silently keep the previous design's proportions.
//
// Only values the user never moved are adopted — a key still holding its
// schema-3 default takes the schema-4 one, anything else is theirs and stays.
var V3_DEFAULTS = {
    barHeight: 30, barRadius: 9, gap: 8, accent: "#9ecbeb", font: "oppo",
    osd: "top"
};

var V3_MOD_OPT_DEFAULTS = {
    ws: { style: "numbers" },
    media: { maxWidth: 220 },
    clock: { dateFormat: "ddd dd" }
};

function adoptRedesign(parsed) {
    if (!parsed || typeof parsed !== "object"
            || (typeof parsed.v === "number" && parsed.v >= 4))
        return parsed;
    var next = clone(parsed);
    Object.keys(V3_DEFAULTS).forEach(function(key) {
        if (next[key] === V3_DEFAULTS[key])
            delete next[key];
    });
    if (next.modOpts && typeof next.modOpts === "object") {
        Object.keys(V3_MOD_OPT_DEFAULTS).forEach(function(id) {
            var entry = next.modOpts[id];
            if (!entry || typeof entry !== "object")
                return;
            Object.keys(V3_MOD_OPT_DEFAULTS[id]).forEach(function(key) {
                if (entry[key] === V3_MOD_OPT_DEFAULTS[id][key])
                    delete entry[key];
            });
        });
    }
    return next;
}

// Schema 7 makes the softer variable face the shell default. As with the
// schema-4 redesign, a stored value equal to the previous default is treated
// as untouched; every other valid font remains an explicit user choice.
function adoptSofterTypography(parsed) {
    if (!parsed || typeof parsed !== "object"
            || (typeof parsed.v === "number" && parsed.v >= 7))
        return parsed;
    var next = clone(parsed);
    if (next.font === undefined || next.font === "urbanist")
        next.font = "google";
    return next;
}

// Schema 10 restores the compact August menubar shown in the repository's
// desktop screenshot, without reviving its fixed layout. As with the earlier
// redesign migration, only values still equal to schema 9's defaults move to
// the new visual baseline; customized geometry, glass, colors and workspace
// presentation remain the user's choices.
var V9_CLASSIC_DEFAULTS = {
    glassEnabled: true,
    barHeight: 46,
    barRadius: 23,
    gap: 10,
    accent: "#5e9bff"
};

var V9_CLASSIC_MOD_OPT_DEFAULTS = {
    ws: { style: "dots" },
    clock: { dateFormat: "ddd d MMM" }
};

function adoptClassicMenubar(parsed) {
    if (!parsed || typeof parsed !== "object"
            || (typeof parsed.v === "number" && parsed.v >= 10))
        return parsed;
    // Schema 3 and unversioned files first pass through adoptRedesign(),
    // which already removes their untouched defaults. Do not then mistake a
    // deliberate old-style value for schema 9's default on the second hop.
    if (typeof parsed.v !== "number" || parsed.v < 4)
        return parsed;
    var next = clone(parsed);
    var untouchedCustomColor = (next.barColorMode === undefined
            || next.barColorMode === "default")
        && next.barCustomHue === 247
        && next.barCustomSaturation === 29
        && next.barCustomLightness === 11;
    if (untouchedCustomColor) {
        delete next.barCustomHue;
        delete next.barCustomSaturation;
        delete next.barCustomLightness;
    }
    Object.keys(V9_CLASSIC_DEFAULTS).forEach(function(key) {
        if (next[key] === V9_CLASSIC_DEFAULTS[key])
            delete next[key];
    });
    if (next.modOpts && typeof next.modOpts === "object") {
        Object.keys(V9_CLASSIC_MOD_OPT_DEFAULTS).forEach(function(id) {
            var entry = next.modOpts[id];
            if (!entry || typeof entry !== "object")
                return;
            Object.keys(V9_CLASSIC_MOD_OPT_DEFAULTS[id]).forEach(function(key) {
                if (entry[key] === V9_CLASSIC_MOD_OPT_DEFAULTS[id][key])
                    delete entry[key];
            });
        });
    }
    return next;
}

// Schema 6 replaces two booleans with explicit visual modes. A v5 floating
// bar whose geometry was never changed becomes the new edge-hugging default;
// customized floating geometry remains floating, and the old edge-to-edge
// option remains attached. The fixed color values are intentionally never
// discarded: paletteMode only chooses which palette is active.
var V5_DEFAULTS = {
    barHeight: 46,
    barRadius: 23,
    gap: 10,
    accent: "#5e9bff",
    barColorMode: "default",
    barCustomHue: 247,
    barCustomSaturation: 29,
    barCustomLightness: 11
};

function migrateBarStyle(parsed, defaultsValue) {
    if (typeof parsed.v === "number" && parsed.v >= 6)
        return enumIn(parsed.barStyle, BAR_STYLES, defaultsValue);
    if (parsed.floating === false)
        return "attached";
    var pristine = intIn(parsed.barHeight, 28, 60, 1, V5_DEFAULTS.barHeight)
            === V5_DEFAULTS.barHeight
        && intIn(parsed.barRadius, 0, 30, 1, V5_DEFAULTS.barRadius)
            === V5_DEFAULTS.barRadius
        && intIn(parsed.gap, 4, 24, 1, V5_DEFAULTS.gap) === V5_DEFAULTS.gap;
    return pristine ? "hug" : "floating";
}

function migratePaletteMode(parsed, defaultsValue) {
    if (typeof parsed.v === "number" && parsed.v >= 6)
        return enumIn(parsed.paletteMode, PALETTE_MODES, defaultsValue);
    if (parsed.accentWall === true)
        return "wallpaper";
    var accent = hexIn(parsed.accent, V5_DEFAULTS.accent).toLowerCase();
    var barMode = enumIn(parsed.barColorMode, BAR_COLOR_IDS,
        V5_DEFAULTS.barColorMode);
    var customHue = intIn(parsed.barCustomHue, 0, 359, 1,
        V5_DEFAULTS.barCustomHue);
    var customSaturation = intIn(parsed.barCustomSaturation, 0, 100, 1,
        V5_DEFAULTS.barCustomSaturation);
    var customLightness = intIn(parsed.barCustomLightness, 0, 100, 1,
        V5_DEFAULTS.barCustomLightness);
    return accent === V5_DEFAULTS.accent && barMode === V5_DEFAULTS.barColorMode
        && customHue === V5_DEFAULTS.barCustomHue
        && customSaturation === V5_DEFAULTS.barCustomSaturation
        && customLightness === V5_DEFAULTS.barCustomLightness
        ? "wallpaper" : "fixed";
}

function merge(raw) {
    var d = defaults();
    if (!raw || typeof raw !== "object")
        return d;
    var parsed = adoptClassicMenubar(
        adoptSofterTypography(adoptRedesign(raw)));
    return {
        wall: nameIn(parsed.wall, d.wall),
        wallDir: pathIn(parsed.wallDir, d.wallDir),
        shuffle: enumIn(parsed.shuffle, ["Off", "15m", "1h", "1d"], d.shuffle),
        themeMode: enumIn(parsed.themeMode, ["dark", "light"], d.themeMode),
        glassEnabled: boolIn(parsed.glassEnabled, d.glassEnabled),
        barColorMode: enumIn(parsed.barColorMode, BAR_COLOR_IDS, d.barColorMode),
        barCustomHue: intIn(parsed.barCustomHue, 0, 359, 1, d.barCustomHue),
        barCustomSaturation: intIn(parsed.barCustomSaturation, 0, 100, 1,
            d.barCustomSaturation),
        barCustomLightness: intIn(parsed.barCustomLightness, 0, 100, 1,
            d.barCustomLightness),
        barHeight: intIn(parsed.barHeight, 28, 60, 1, d.barHeight),
        barRadius: intIn(parsed.barRadius, 0, 30, 1, d.barRadius),
        font: enumIn(parsed.font, FONT_IDS, d.font),
        accent: hexIn(parsed.accent, d.accent),
        paletteMode: migratePaletteMode(parsed, d.paletteMode),
        position: enumIn(parsed.position, ["top", "bottom"], d.position),
        barStyle: migrateBarStyle(parsed, d.barStyle),
        gap: intIn(parsed.gap, 4, 24, 1, d.gap),
        autoHide: boolIn(parsed.autoHide, d.autoHide),
        exclusive: boolIn(parsed.exclusive, d.exclusive),
        clock24: boolIn(parsed.clock24, d.clock24),
        unit: enumIn(parsed.unit, ["c", "f"], d.unit),
        warmth: intIn(parsed.warmth, 1900, 4500, 50, d.warmth),
        osd: enumIn(parsed.osd, ["top", "bottom"], d.osd),
        pollMax: enumIn(parsed.pollMax, [60, 300, 600], d.pollMax),
        scrollFactor: realIn(parsed.scrollFactor, 0.2, 2.0, 0.1, d.scrollFactor),
        nightLight: boolIn(parsed.nightLight, d.nightLight),
        idleInhibited: boolIn(parsed.idleInhibited, d.idleInhibited),
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
        modOpts: normalizeModOpts(parsed.modOpts)
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
    return hslToHex(degrees, 50, 75);
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

// Distinguishing "no settings yet" from "settings we could not read" is what
// keeps a corrupt file recoverable: both merge to defaults, but only the empty
// case may be overwritten. Returns { status, value } where status is one of:
//   "empty"   — nothing on disk yet (or a whitespace-only file); first run.
//   "ok"      — a settings object; value is it.
//   "corrupt" — bytes exist but are not a settings object. Value is null and
//               the caller must preserve the file before saving over it.
function parse(text) {
    if (typeof text !== "string" || text.trim() === "")
        return { status: "empty", value: null };
    var parsed;
    try {
        parsed = JSON.parse(text);
    } catch (e) {
        return { status: "corrupt", value: null };
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
        return { status: "corrupt", value: null };
    return { status: "ok", value: parsed };
}

var exported = {
    VERSION: VERSION,
    BAR_STYLES: BAR_STYLES,
    PALETTE_MODES: PALETTE_MODES,
    MODULE_IDS: MODULE_IDS,
    RETIRED_MODULE_IDS: RETIRED_MODULE_IDS,
    MODULE_GROUPS: MODULE_GROUPS,
    moduleGroup: moduleGroup,
    DETAIL_IDS: DETAIL_IDS,
    DETAIL_POLICIES: DETAIL_POLICIES,
    FONT_CHOICES: FONT_CHOICES,
    FONT_IDS: FONT_IDS,
    BAR_COLOR_CHOICES: BAR_COLOR_CHOICES,
    BAR_COLOR_IDS: BAR_COLOR_IDS,
    BAR_COLOR_PRESETS: BAR_COLOR_PRESETS,
    defaults: defaults,
    defaultMods: defaultMods,
    defaultModOpts: defaultModOpts,
    normalizeMods: normalizeMods,
    normalizeModOpts: normalizeModOpts,
    migrateMods: migrateMods,
    migrateBarStyle: migrateBarStyle,
    migratePaletteMode: migratePaletteMode,
    pathIn: pathIn,
    detailIn: detailIn,
    repoListIn: repoListIn,
    MAX_WATCHED_REPOS: MAX_WATCHED_REPOS,
    quietRange: quietRange,
    quietActive: quietActive,
    formatMinutes: formatMinutes,
    hueToHex: hueToHex,
    hexHue: hexHue,
    hslToHex: hslToHex,
    resolveBarColor: resolveBarColor,
    relativeLuminance: relativeLuminance,
    contrastRatio: contrastRatio,
    foregroundFor: foregroundFor,
    ensureContrast: ensureContrast,
    barPalette: barPalette,
    semanticPalette: semanticPalette,
    clone: clone,
    restoreSnapshot: restoreSnapshot,
    merge: merge,
    serialize: serialize,
    parse: parse
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
