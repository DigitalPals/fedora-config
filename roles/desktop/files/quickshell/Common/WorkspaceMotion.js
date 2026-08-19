// Workspace geometry and direction selection without Hyprland or Qt state.

var CELL_WIDTH = 22;
var LEADING_MS = 120;
var TRAILING_MS = 300;

function visibleIds(slotCount, existingIds, focusedId, hideEmpty) {
    var existing = {};
    (Array.isArray(existingIds) ? existingIds : []).forEach(function(id) {
        if (Number.isInteger(id) && id > 0)
            existing[id] = true;
    });
    var count = Math.max(0, Math.floor(Number(slotCount) || 0));
    var out = [];
    for (var id = 1; id <= count; id++) {
        if (!hideEmpty || existing[id] || id === focusedId)
            out.push(id);
    }
    return out;
}

function indicatorBounds(ids, focusedId) {
    var index = Array.isArray(ids) ? ids.indexOf(focusedId) : -1;
    if (index < 0)
        return null;
    return { left: index * CELL_WIDTH + 2, right: index * CELL_WIDTH + 20 };
}

function edgeDurations(previousId, nextId, animate) {
    if (!animate || !Number.isFinite(previousId) || !Number.isFinite(nextId)
            || previousId <= 0 || nextId <= 0 || previousId === nextId)
        return { left: 0, right: 0, direction: 0 };
    if (nextId > previousId)
        return { left: TRAILING_MS, right: LEADING_MS, direction: 1 };
    return { left: LEADING_MS, right: TRAILING_MS, direction: -1 };
}

var exported = {
    CELL_WIDTH: CELL_WIDTH,
    LEADING_MS: LEADING_MS,
    TRAILING_MS: TRAILING_MS,
    visibleIds: visibleIds,
    indicatorBounds: indicatorBounds,
    edgeDurations: edgeDurations
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
