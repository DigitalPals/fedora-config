import QtQuick

// Whether the pointer is really over `target`, as opposed to whatever that
// item's own MouseArea last heard.
//
// A MouseArea on a layer surface can miss its exit event — mapping a second
// surface over the pointer is enough — and then `containsMouse` stays true
// with nothing left to clear it. Everything bound to it sticks: the chip keeps
// its hover fill, and the tooltip stays on screen long after the pointer has
// gone.
//
// The bar's full-window HoverHandler is the second opinion. It reports the
// pointer leaving the surface when the MouseArea did not, and it publishes the
// position, which is what tells a hover belonging to a neighbouring module
// apart from one belonging to this target.
//
// This is deliberately one shared object per hover target rather than a check
// per consumer: the chip's fill and its tooltip have to agree, and the only
// way to guarantee that is for both to read the same answer.
QtObject {
    id: root

    // The bar carrying the shared pointer state. Required: with nothing to
    // check against, the stale value would simply stand.
    required property Bar host
    // The item the pointer is claimed to be over. The hover region is this
    // item's rectangle, so it is whatever the MouseArea fills.
    required property Item target
    // The caller's first opinion. Legacy non-visual checks pass their local
    // MouseArea state; BarHover passes true so the bar-wide scene hit test is
    // authoritative for every visual hover surface.
    required property bool hovered

    readonly property bool over: {
        // Skip the scene mapping while not hovered. This also drops the
        // binding's dependency on tooltipPointerPosition, so an idle module
        // costs nothing on pointer moves elsewhere in the bar.
        if (!root.hovered)
            return false;
        // `host` is assigned after construction, and a delegate's `target` can
        // be null just as briefly. No pointer truth, no hover: a module cannot
        // be hovered before it has been laid out.
        if (!root.host || !root.host.tooltipPointerInside || !root.target)
            return false;
        const scenePoint = root.host.tooltipPointerPosition;
        const localPoint = root.target.mapFromItem(null,
            scenePoint.x, scenePoint.y);
        return localPoint.x >= 0 && localPoint.x <= root.target.width
            && localPoint.y >= 0 && localPoint.y <= root.target.height;
    }
}
