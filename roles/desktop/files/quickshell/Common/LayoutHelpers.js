// Pure geometry/input helpers shared by QML and Node tests.

var COMPACT_ORDER = ["media", "weather", "clock", "t3", "vol", "batt", "usage"];

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
    var entries = Array.isArray(options.entries) ? options.entries : [];
    var compact = [];

    function apply(entry) {
        if (!entry || compact.indexOf(entry.id) !== -1)
            return;
        compact.push(entry.id);
        if (entry.col in widths)
            widths[entry.col] = Math.max(0, widths[entry.col] - Math.max(0, entry.saving || 0));
    }

    function geometry() {
        var desired = (available - widths.center) / 2;
        var rightX = available - widths.right;
        return {
            desired: desired,
            rightX: rightX,
            fits: widths.left + gutter <= desired
                && desired + widths.center + gutter <= rightX
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
        var maxX = state.rightX - gutter - widths.center;
        if (maxX >= minX) {
            centerX = clamp(state.desired, minX, maxX);
            shifted = Math.abs(centerX - state.desired) > 0.01;
            state.fits = true;
        }
    }

    return {
        compact: compact,
        widths: widths,
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

var exported = {
    COMPACT_ORDER: COMPACT_ORDER,
    stackedDropIndex: stackedDropIndex,
    fitBar: fitBar,
    accumulateWheel: accumulateWheel
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
