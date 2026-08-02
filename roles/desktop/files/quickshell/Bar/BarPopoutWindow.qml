import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../Common"

// Popouts use their own layer surface. Their content and native height may
// change while switching modules, but the menubar's surface remains stable.
PanelWindow {
    id: root

    required property Bar bar

    // Every output has a popout window, but only the one under the mapped
    // bar may show a panel or take the focus grab.
    readonly property bool live: bar.visible

    visible: live && Popouts.open
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Math.max(1, leftPopout.requiredHeight,
        centerPopout.requiredHeight, rightPopout.requiredHeight)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    mask: Region {
        regions: [
            Region { item: leftPopout.maskItem },
            Region { item: centerPopout.maskItem },
            Region { item: rightPopout.maskItem }
        ]
    }

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "qs-bar-popout"

    HyprlandFocusGrab {
        active: root.live && Popouts.open
        windows: [root.bar, root]
        onCleared: Popouts.close()
    }

    IslandPopout {
        id: leftPopout
        live: root.live
        islandRect: root.bar.leftIslandRect
        isle: "left"
    }

    IslandPopout {
        id: centerPopout
        live: root.live
        islandRect: root.bar.centerIslandRect
        isle: "center"
    }

    IslandPopout {
        id: rightPopout
        live: root.live
        islandRect: root.bar.rightIslandRect
        isle: "right"
    }
}
