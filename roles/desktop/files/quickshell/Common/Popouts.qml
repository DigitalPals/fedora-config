pragma Singleton
import QtQuick
import Quickshell
import "PanelRegistryData.js" as PanelRegistry

// Shared state for the bar's detached popouts. Every view hangs from its
// triggering module, the host morphs one card between modules, and only one
// popout is open shell-wide. Esc or clicking the desktop closes it.
Singleton {
    id: root

    property bool open: false
    property string currentName: ""
    property string island: ""

    // Window-coordinate rect of the module the popout hangs under, so the
    // surface can sit at the module instead of at the edge of the section
    // that happens to hold it. Zero width means "no anchor given" — fall
    // back to the island alignment. Snapshotted at open: a bar re-layout
    // while a panel is open leaves it where it was drawn.
    property rect anchorRect: Qt.rect(0, 0, 0, 0)

    // Emitted once per state change, after every property has settled, so
    // the island hosts never observe a half-updated (name, island) pair.
    signal changed

    // Island a popout opens on when the caller does not say (IPC, bar
    // modules). Panels opened from inside another popout may override —
    // e.g. the Control Center morphs to Wi-Fi details on the right island.
    // Derived, not hand-maintained: see Common/PanelRegistryData.js.
    readonly property var defaultIsland: PanelRegistry.islandMap()

    function openPanel(name, isle, anchor) {
        // IPC accepts an arbitrary string. Mapping a one-pixel focus-grabbing
        // layer for an unknown name leaves an invisible ghost surface because
        // the host has no component to present.
        if (PanelRegistry.byName(name) === null) {
            console.warn("Ignoring unknown popout:", name);
            return;
        }
        island = isle ?? defaultIsland[name] ?? "right";
        // Callers with no module to point at — the IPC handler, or one
        // popover morphing into another — keep the surface where it is
        // rather than making it jump to the section edge.
        if (anchor !== undefined)
            anchorRect = anchor;
        else if (!open)
            anchorRect = Qt.rect(0, 0, 0, 0);
        currentName = name;
        open = true;
        changed();
    }

    function toggle(name, isle, anchor) {
        if (open && currentName === name)
            close();
        else
            openPanel(name, isle, anchor);
    }

    function close() {
        if (!open)
            return;
        open = false;
        changed();
    }
}
