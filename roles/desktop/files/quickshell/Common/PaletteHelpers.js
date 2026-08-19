// Pure validation for Matugen output and the wallpaper-palette cache. Keep Qt
// APIs out of this file so malformed-output and stale-result behavior can be
// tested without starting the shell.

var CACHE_VERSION = 1;

var ROLE_MAP = {
    background: "background",
    surface: "surface",
    surface_container_low: "surfaceContainerLow",
    surface_container: "surfaceContainer",
    surface_container_high: "surfaceContainerHigh",
    on_surface: "onSurface",
    on_surface_variant: "onSurfaceVariant",
    primary: "primary",
    primary_container: "primaryContainer",
    on_primary: "onPrimary",
    outline_variant: "outlineVariant",
    error: "error",
    error_container: "errorContainer",
    on_error: "onError"
};

var ROLE_KEYS = Object.keys(ROLE_MAP);

function parseObject(value) {
    if (typeof value !== "string")
        return value && typeof value === "object" && !Array.isArray(value) ? value : null;
    try {
        var parsed = JSON.parse(value);
        return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null;
    } catch (error) {
        return null;
    }
}

function colorIn(value) {
    return typeof value === "string" && /^#[0-9a-fA-F]{6}$/.test(value)
        ? value.toLowerCase() : "";
}

// Matugen emits { colors: { role: { dark, default, light } } }. Unknown roles
// are ignored and all required light/dark values must be present.
function sanitizeMatugen(value) {
    var parsed = parseObject(value);
    var colors = parsed && parsed.colors;
    if (!colors || typeof colors !== "object" || Array.isArray(colors))
        return null;
    var palette = { dark: {}, light: {} };
    for (var i = 0; i < ROLE_KEYS.length; i++) {
        var inputName = ROLE_KEYS[i];
        var outputName = ROLE_MAP[inputName];
        var role = colors[inputName];
        if (!role || typeof role !== "object")
            return null;
        var dark = colorIn(role.dark);
        var light = colorIn(role.light);
        if (dark === "" || light === "")
            return null;
        palette.dark[outputName] = dark;
        palette.light[outputName] = light;
    }
    return palette;
}

function sanitizePalette(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)
            || !value.dark || !value.light)
        return null;
    var out = { dark: {}, light: {} };
    for (var variantIndex = 0; variantIndex < 2; variantIndex++) {
        var variant = variantIndex === 0 ? "dark" : "light";
        for (var i = 0; i < ROLE_KEYS.length; i++) {
            var name = ROLE_MAP[ROLE_KEYS[i]];
            var color = colorIn(value[variant][name]);
            if (color === "")
                return null;
            out[variant][name] = color;
        }
    }
    return out;
}

function activeVariant(palette, themeMode) {
    var clean = sanitizePalette(palette);
    if (!clean)
        return null;
    return themeMode === "light" ? clean.light : clean.dark;
}

function makeCache(identity, palette) {
    var clean = sanitizePalette(palette);
    if (typeof identity !== "string" || identity === "" || !clean)
        return null;
    return { v: CACHE_VERSION, identity: identity, palette: clean };
}

function readCache(value, identity) {
    var parsed = parseObject(value);
    if (!parsed || parsed.v !== CACHE_VERSION || parsed.identity !== identity)
        return null;
    return sanitizePalette(parsed.palette);
}

function serializeCache(identity, palette) {
    var cache = makeCache(identity, palette);
    return cache ? JSON.stringify(cache, null, 2) + "\n" : "";
}

function resultIsCurrent(resultIdentity, currentIdentity) {
    return typeof resultIdentity === "string" && resultIdentity !== ""
        && resultIdentity === currentIdentity;
}

function selectOrFallback(palette, themeMode, fallback, enabled) {
    var selected = enabled ? activeVariant(palette, themeMode) : null;
    return selected || fallback;
}

var exported = {
    CACHE_VERSION: CACHE_VERSION,
    ROLE_MAP: ROLE_MAP,
    ROLE_KEYS: ROLE_KEYS,
    colorIn: colorIn,
    sanitizeMatugen: sanitizeMatugen,
    sanitizePalette: sanitizePalette,
    activeVariant: activeVariant,
    makeCache: makeCache,
    readCache: readCache,
    serializeCache: serializeCache,
    resultIsCurrent: resultIsCurrent,
    selectOrFallback: selectOrFallback
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
