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

    // Map immediately on open intent so the first Loader can incubate. Once
    // Popouts.open drops, `presented` keeps the surface alive through the
    // closing animation.
    visible: live && (Popouts.open || popout.presented)
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Math.max(1, popout.requiredHeight)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    mask: Region { item: popout.maskItem }

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "qs-bar-popout"

    HyprlandFocusGrab {
        active: root.live && Popouts.open
        windows: [root.bar, root]
        onCleared: Popouts.close()
    }

    IslandPopout {
        id: popout
        width: root.bar.width
        height: root.implicitHeight
        live: root.live
        leftIslandRect: root.bar.leftIslandRect
        centerIslandRect: root.bar.centerIslandRect
        rightIslandRect: root.bar.rightIslandRect
    }
}
