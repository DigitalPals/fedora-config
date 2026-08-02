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

    // Emitted once per state change, after every property has settled, so
    // the island hosts never observe a half-updated (name, island) pair.
    signal changed

    // Island a popout opens on when the caller does not say (IPC, bar
    // modules). Panels opened from inside another popout may override —
    // e.g. the Control Center morphs to Wi-Fi details on the right island.
    readonly property var defaultIsland: ({
            control: "right",
            calendar: "center",
            media: "center",
            usage: "right",
            audio: "right",
            wifi: "right",
            bluetooth: "right",
            battery: "right",
            notifications: "right"
        })

    function openPanel(name, isle) {
        island = isle ?? defaultIsland[name] ?? "right";
        currentName = name;
        open = true;
        changed();
    }

    function toggle(name, isle) {
        if (open && currentName === name)
            close();
        else
            openPanel(name, isle);
    }

    function close() {
        if (!open)
            return;
        open = false;
        changed();
    }
}
