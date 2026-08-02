pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    // Name of the open popover ("" = closed) and its anchor edge in bar
    // window coordinates. align: 0 = popover's left edge at anchorX,
    // 1 = popover's right edge at anchorX. originRect is the clicked
    // module's screen rect the modal morphs out of; clusterRect is the
    // bar island the modal stays visually attached to.
    property string current: ""
    property real anchorX: 0
    property int align: 1
    property var originRect: ({ x: 0, y: 0, w: 40, h: 34 })
    property var clusterRect: ({ x: 0, y: 8, w: 0, h: 34 })

    // Bar island rects, published by the bar (used by IPC-driven opens).
    property var clusters: ({})

    // True while the close animation plays; the window clears `current`
    // via finishClose() when it ends.
    property bool closing: false

    function open(name, x, alignMode, rect, cluster) {
        closing = false;
        anchorX = x;
        align = alignMode;
        originRect = rect !== undefined ? rect : { x: x - 20, y: 8, w: 40, h: 34 };
        if (cluster !== undefined)
            clusterRect = cluster;
        current = name;
    }

    function toggle(name, x, alignMode, rect, cluster) {
        if (current === name && !closing)
            close();
        else
            open(name, x, alignMode, rect, cluster);
    }

    function close() {
        if (current === "" || closing)
            return;
        closing = true;
    }

    function finishClose() {
        current = "";
        closing = false;
    }
}
