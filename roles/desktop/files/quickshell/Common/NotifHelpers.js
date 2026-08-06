// Pure notification presentation helpers shared by QML and Node tests.
// Keep this file free of Qt APIs so notification parsing stays deterministic.

var MIN_TIMEOUT_MS = 8000;
var MAX_TIMEOUT_MS = 12000;

function textValue(value) {
    return typeof value === "string" ? value : "";
}

function decodeEntities(value) {
    var named = {
        amp: "&",
        apos: "'",
        gt: ">",
        lt: "<",
        nbsp: " ",
        quot: "\""
    };
    return value.replace(/&(#(?:x[0-9a-f]+|[0-9]+)|[a-z]+);/gi,
        function(match, entity) {
            var lower = entity.toLowerCase();
            if (lower.charAt(0) !== "#")
                return Object.prototype.hasOwnProperty.call(named, lower)
                    ? named[lower] : match;
            var hexadecimal = lower.charAt(1) === "x";
            var codePoint = parseInt(lower.slice(hexadecimal ? 2 : 1),
                hexadecimal ? 16 : 10);
            if (!isFinite(codePoint) || codePoint <= 0 || codePoint > 0x10ffff)
                return match;
            if (codePoint <= 0xffff)
                return String.fromCharCode(codePoint);
            codePoint -= 0x10000;
            return String.fromCharCode(0xd800 + (codePoint >> 10),
                0xdc00 + (codePoint & 0x3ff));
        });
}

function stripMarkup(value) {
    var text = textValue(value)
        .replace(/\r\n?/g, "\n")
        .replace(/<\s*br\s*\/?\s*>/gi, "\n")
        .replace(/<\s*\/?\s*(?:div|p|li)(?:\s[^>]*)?>/gi, "\n")
        .replace(/<[^>]*>/g, "");
    text = decodeEntities(text).replace(/[\u200b-\u200d\ufeff]/g, "");
    var lines = text.split("\n").map(function(line) {
        return line.replace(/[\t\f\v ]+/g, " ").trim();
    });
    return lines.join("\n").replace(/\n{3,}/g, "\n\n").trim();
}

function singleLine(value) {
    return stripMarkup(value).replace(/\s+/g, " ").trim();
}

function normalizeOrigin(value) {
    var origin = singleLine(value).toLowerCase();
    if (origin === "")
        return "";
    origin = origin.replace(/^origin:\s*/i, "")
        .replace(/^[a-z][a-z0-9+.-]*:\/\//i, "")
        .replace(/^\/\//, "");
    origin = origin.split(/[\/?#]/, 1)[0];
    if (origin.indexOf("@") !== -1)
        origin = origin.slice(origin.lastIndexOf("@") + 1);
    if (/^\[[0-9a-f:]+\](?::\d+)?$/i.test(origin))
        return origin.replace(/:\d+$/, "");
    origin = origin.replace(/:\d+$/, "").replace(/\.+$/, "");
    if (origin === "localhost" || /^(?:\d{1,3}\.){3}\d{1,3}$/.test(origin))
        return origin;
    if (origin.indexOf(" ") !== -1 || origin.indexOf(".") === -1
            || !/^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/.test(origin))
        return "";
    return origin;
}

function isBrowser(appName, desktopEntry) {
    var identity = (textValue(appName) + " " + textValue(desktopEntry)).toLowerCase();
    return /(?:^|[^a-z0-9])(?:google[ -]?chrome(?:-stable)?|chrome|chromium|brave|vivaldi|opera|microsoft[ -]?edge|msedge)(?:[^a-z0-9]|$)/
        .test(identity);
}

function parseLegacyBody(value) {
    var body = stripMarkup(value);
    var separator = body.search(/\n\s*\n/);
    if (separator === -1)
        return { origin: "", body: body };
    var candidate = normalizeOrigin(body.slice(0, separator));
    if (candidate === "")
        return { origin: "", body: body };
    return {
        origin: candidate,
        body: body.slice(separator).replace(/^\s+/, "").trim()
    };
}

function hintValue(hints, key) {
    if (!hints || typeof hints !== "object")
        return "";
    return textValue(hints[key]);
}

function comparableText(value) {
    return singleLine(value).toLowerCase();
}

function displayNameForOrigin(origin) {
    return origin === "web.whatsapp.com" ? "WhatsApp" : origin;
}

function derivePresentation(notification) {
    notification = notification || {};
    var browser = isBrowser(notification.appName, notification.desktopEntry);
    var rawBody = stripMarkup(notification.body);
    var legacy = parseLegacyBody(notification.body);
    var hintedOrigin = normalizeOrigin(notification.originName
        || hintValue(notification.hints, "x-kde-origin-name"));
    var origin = browser ? (hintedOrigin || legacy.origin) : "";
    var body = rawBody;
    if (origin !== "" && legacy.origin === origin)
        body = legacy.body;

    var summary = singleLine(notification.summary);
    if (body !== "" && comparableText(body) === comparableText(summary))
        body = "";

    return {
        browser: browser,
        displayAppName: origin !== "" ? displayNameForOrigin(origin)
            : (singleLine(notification.appName) || "Notification"),
        displaySummary: summary,
        displayBody: body,
        webOrigin: origin,
        brandIcon: origin === "web.whatsapp.com" ? "whatsapp" : ""
    };
}

function actionIdentifier(action) {
    if (!action || typeof action !== "object")
        return "";
    return textValue(action.identifier || action.id || action.key).toLowerCase();
}

function actionList(actions) {
    if (!actions || typeof actions.length !== "number")
        return [];
    var list = [];
    for (var i = 0; i < actions.length; i++)
        list.push(actions[i]);
    return list;
}

function defaultAction(actions) {
    var list = actionList(actions);
    for (var i = 0; i < list.length; i++) {
        if (actionIdentifier(list[i]) === "default")
            return list[i];
    }
    return null;
}

function secondaryActions(actions) {
    var list = actionList(actions);
    return list.filter(function(action) {
        var identifier = actionIdentifier(action);
        return identifier !== "default" && identifier !== "close"
            && singleLine(action && action.text) !== "";
    }).slice(0, 2);
}

function visibleCharacterCount(entry) {
    entry = entry || {};
    return singleLine(entry.displaySummary || entry.summary).length
        + singleLine(entry.displayBody || entry.body).length;
}

function timeoutMs(visibleCharacters, requestedSeconds) {
    if (typeof requestedSeconds === "number" && isFinite(requestedSeconds)
            && requestedSeconds > 0) {
        return Math.max(MIN_TIMEOUT_MS,
            Math.min(MAX_TIMEOUT_MS, Math.round(requestedSeconds * 1000)));
    }
    var count = typeof visibleCharacters === "number" && isFinite(visibleCharacters)
        ? Math.max(0, Math.floor(visibleCharacters)) : 0;
    var extraSeconds = count <= 80 ? 0 : Math.ceil((count - 80) / 40);
    return Math.min(MAX_TIMEOUT_MS, MIN_TIMEOUT_MS + extraSeconds * 1000);
}

// This describes precedence without doing any Qt theme lookups. Web sources
// deliberately omit the browser's app icon once their origin is known.
function iconPreference(entry) {
    entry = entry || {};
    var choices = [];
    if (textValue(entry.brandIcon) !== "")
        choices.push({ kind: "brand", value: entry.brandIcon });
    if (textValue(entry.webOrigin) !== "") {
        if (textValue(entry.image) !== "")
            choices.push({ kind: "image", value: entry.image });
        choices.push({ kind: "web-fallback", value: "" });
        return choices;
    }
    if (textValue(entry.appIcon) !== "")
        choices.push({ kind: "app-icon", value: entry.appIcon });
    if (textValue(entry.desktopEntry) !== "")
        choices.push({ kind: "desktop-entry", value: entry.desktopEntry });
    if (textValue(entry.image) !== "")
        choices.push({ kind: "image", value: entry.image });
    choices.push({ kind: "generic-fallback", value: "" });
    return choices;
}

var exported = {
    MIN_TIMEOUT_MS: MIN_TIMEOUT_MS,
    MAX_TIMEOUT_MS: MAX_TIMEOUT_MS,
    decodeEntities: decodeEntities,
    stripMarkup: stripMarkup,
    singleLine: singleLine,
    normalizeOrigin: normalizeOrigin,
    isBrowser: isBrowser,
    parseLegacyBody: parseLegacyBody,
    derivePresentation: derivePresentation,
    actionIdentifier: actionIdentifier,
    defaultAction: defaultAction,
    secondaryActions: secondaryActions,
    visibleCharacterCount: visibleCharacterCount,
    timeoutMs: timeoutMs,
    iconPreference: iconPreference
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
