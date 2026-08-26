// Pure presentation helpers for the dedicated battery view. UPower remains
// the source of truth in QML; this module only gives its telemetry stable,
// testable text and turns the one-shot sysfs cycle read into one value.
// Keep this file free of Qt APIs so the same edge cases run under Node.

var MISSING = "—";

function finiteNumber(value) {
    if (value === undefined || value === null || typeof value === "boolean")
        return NaN;
    if (typeof value === "string" && value.trim() === "")
        return NaN;
    var number = Number(value);
    return isFinite(number) ? number : NaN;
}

// Capacity cannot meaningfully be zero. A fixed decimal keeps this column
// from changing width as the backend settles on its final floating value.
function formatWh(value) {
    var number = finiteNumber(value);
    return number > 0 ? number.toFixed(1) + " Wh" : MISSING;
}

// UPower signs changeRate by direction. This panel labels direction with its
// state text, so the telemetry value is deliberately magnitude-only. Zero is
// useful at full charge and must remain distinct from a missing reading.
function formatW(value) {
    var number = finiteNumber(value);
    return isFinite(number) ? Math.abs(number).toFixed(1) + " W" : MISSING;
}

function pad2(value) {
    return value < 10 ? "0" + value : String(value);
}

function formatDuration(seconds) {
    var number = finiteNumber(seconds);
    if (!(number > 0))
        return MISSING;
    var totalMinutes = Math.max(1, Math.round(number / 60));
    var hours = Math.floor(totalMinutes / 60);
    var minutes = totalMinutes % 60;
    return hours > 0 ? hours + " h " + pad2(minutes) + " min"
        : totalMinutes + " min";
}

// The process emits one line per lexically sorted BAT*/cycle_count file.
// Preserve malformed positions as an em dash: on a two-pack machine, one bad
// counter must not make the other pack look like the only battery installed.
function parseCycleCounts(output) {
    if (typeof output !== "string")
        return MISSING;

    var lines = output.replace(/\r/g, "").split("\n");
    while (lines.length > 0 && lines[lines.length - 1] === "")
        lines.pop();
    if (lines.length === 0)
        return MISSING;

    return lines.map(function (line) {
        var value = line.trim();
        if (!/^\d+$/.test(value))
            return MISSING;
        return String(parseInt(value, 10));
    }).join(" · ");
}

var exported = {
    MISSING: MISSING,
    formatWh: formatWh,
    formatW: formatW,
    formatDuration: formatDuration,
    parseCycleCounts: parseCycleCounts
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
