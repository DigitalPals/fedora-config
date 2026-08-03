pragma Singleton
import QtQuick
import Quickshell

// Shared state for the connected island popouts (design t5): every view
// is fused to its bar island, each island owns one popout surface, and
// only one popout is open shell-wide. Esc or clicking the desktop closes.
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
    readonly property var defaultIsland: ({
            control: "right",
            calendar: "center",
            media: "left",
            weather: "center",
            usage: "right",
            t3code: "right",
            audio: "right",
            wifi: "right",
            bluetooth: "right",
            tailscale: "right",
            battery: "right",
            notifications: "right"
        })

    function openPanel(name, isle, anchor) {
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
