// Pure geometry/input helpers shared by QML and Node tests.

// Which module gives up its detail text first when the bar runs out of room.
// Mirrors the design's two breakpoints: the counts and labels in the right
// cluster go at the first one, the weather segment and the media title at the
// second, and the clock's own date only as a last resort.
var COMPACT_ORDER = ["media", "updates", "t3", "usage", "gh", "weather",
    "clock", "vol", "batt"];

// Consecutive modules that draw the same way share one rounded background:
// the T3/usage/GitHub chips sit in a single group pill, and the volume,
// Wi-Fi, Bluetooth and battery glyphs sit in the status pill that opens the
// Control Center. "solo" modules bring their own pill and never merge, so two
// of them in a row stay two pills.
//
// Grouping is by adjacency, not by kind: moving a module between others in
// the settings window splits or joins the pill exactly where it was dropped,
// which is the only behaviour that matches what the drag preview showed.
function groupModules(entries, groupOf) {
    var out = [];
    (entries || []).forEach(function(entry, index) {
        var kind = typeof groupOf === "function" ? groupOf(entry.id) : "solo";
        var last = out.length > 0 ? out[out.length - 1] : null;
        if (last && last.kind === kind && kind !== "solo") {
            last.items.push({ entry: entry, index: index, at: last.items.length });
            return;
        }
        out.push({
            kind: kind,
            key: kind + ":" + index,
            items: [{ entry: entry, index: index, at: 0 }]
        });
    });
    return out;
}

function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}

function stackedDropIndex(columns, y) {
    if (!Array.isArray(columns) || columns.length === 0)
        return null;
    var column = columns[columns.length - 1];
    for (var i = 0; i < columns.length; i++) {
        var candidate = columns[i];
        if (y < candidate.y + candidate.height) {
            column = candidate;
            break;
        }
    }
    var local = y - column.y - column.rowsStart;
    var index = clamp(Math.floor((local + column.pitch / 2) / column.pitch), 0, column.length);
    return { col: column.id, idx: index };
}

function fitBar(options) {
    options = options || {};
    var available = Math.max(0, (options.width || 0) - 2 * (options.sideMargin || 0));
    var gutter = options.gutter === undefined ? 8 : options.gutter;
    var widths = {
        left: Math.max(0, options.widths && options.widths.left || 0),
        center: Math.max(0, options.widths && options.widths.center || 0),
        right: Math.max(0, options.widths && options.widths.right || 0)
    };
    var asymmetricCenter = !!options.centerExtents;
    var center = asymmetricCenter ? {
        left: Math.max(0, Number(options.centerExtents.left) || 0),
        right: Math.max(0, Number(options.centerExtents.right) || 0)
    } : {
        left: widths.center / 2,
        right: widths.center / 2
    };
    widths.center = center.left + center.right;
    var entries = Array.isArray(options.entries) ? options.entries : [];
    var compact = [];

    function apply(entry) {
        if (!entry || compact.indexOf(entry.id) !== -1)
            return;
        compact.push(entry.id);
        if (entry.col in widths) {
            widths[entry.col] = Math.max(0, widths[entry.col] - Math.max(0, entry.saving || 0));
            if (entry.col === "center") {
                var amount = Math.max(0, entry.saving || 0);
                if (asymmetricCenter) {
                    var side = entry.centerSide === "left" ? "left" : "right";
                    center[side] = Math.max(0, center[side] - amount);
                } else {
                    center.left = Math.max(0, center.left - amount / 2);
                    center.right = Math.max(0, center.right - amount / 2);
                }
            }
        }
    }

    function geometry() {
        // Pin the semantic center (the clock slot), not the midpoint of a
        // center cluster whose left and right contents can have different
        // widths. Revealing quick actions then grows outward from the clock.
        var desired = available / 2 - center.left;
        var rightX = available - widths.right;
        return {
            desired: desired,
            rightX: rightX,
            fits: widths.left + gutter <= desired
                && desired + center.left + center.right + gutter <= rightX
        };
    }

    entries.filter(function(entry) { return entry.policy === "compact"; }).forEach(apply);
    var ordered = [];
    ["auto", "prefer"].forEach(function(policy) {
        COMPACT_ORDER.forEach(function(id) {
            var entry = entries.find(function(item) {
                return item.id === id && item.policy === policy;
            });
            if (entry)
                ordered.push(entry);
        });
    });

    var state = geometry();
    for (var i = 0; !state.fits && i < ordered.length; i++) {
        apply(ordered[i]);
        state = geometry();
    }

    var centerX = state.desired;
    var shifted = false;
    if (!state.fits) {
        var minX = widths.left + gutter;
        var maxX = state.rightX - gutter - center.left - center.right;
        if (maxX >= minX) {
            centerX = clamp(state.desired, minX, maxX);
            shifted = Math.abs(centerX - state.desired) > 0.01;
            state.fits = true;
        }
    }

    return {
        compact: compact,
        widths: widths,
        centerExtents: center,
        centerX: centerX,
        centerOffset: centerX - state.desired,
        shifted: shifted,
        fits: state.fits
    };
}

function accumulateWheel(accumulator, delta, threshold) {
    var limit = Math.max(1, threshold || 120);
    var total = (Number(accumulator) || 0) + (Number(delta) || 0);
    var steps = total < 0 ? Math.ceil(total / limit) : Math.floor(total / limit);
    return { accumulator: total - steps * limit, steps: steps };
}

// Shorten only the flare that would cross a rounded outer bar tangent. A
// roomy edge popout and the side opposite its island retain the full radius.
function edgeFlareRadii(options) {
    options = options || {};
    var island = options.island;
    var barRadius = Math.max(0, Number(options.barRadius) || 0);
    var popRadius = Math.max(0, Number(options.popRadius) || 0);
    var radii = { left: popRadius, right: popRadius };
    if (!options.floating || barRadius <= 0 || popRadius <= 0)
        return radii;

    var sideMargin = Number(options.sideMargin) || 0;
    var bodyX = Number(options.bodyX) || 0;
    var bodyW = Math.max(0, Number(options.bodyW) || 0);
    if (island === "left") {
        var leftRoom = bodyX - (sideMargin + barRadius);
        radii.left = Math.max(1, Math.min(popRadius, leftRoom));
    } else if (island === "right") {
        var rightTangent = (Number(options.width) || 0) - sideMargin - barRadius;
        var rightRoom = rightTangent - (bodyX + bodyW);
        radii.right = Math.max(1, Math.min(popRadius, rightRoom));
    }
    return radii;
}

var exported = {
    COMPACT_ORDER: COMPACT_ORDER,
    groupModules: groupModules,
    stackedDropIndex: stackedDropIndex,
    fitBar: fitBar,
    accumulateWheel: accumulateWheel,
    edgeFlareRadii: edgeFlareRadii
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
