import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../Common"
import "../Common/PanelRegistryData.js" as PanelRegistry

// Panels use their own layer surface. Their content and native height may
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
        top: Settings.position === "top"
        bottom: Settings.position === "bottom"
        left: true
        right: true
    }
    implicitHeight: Math.max(1, popout.requiredHeight)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    mask: Region { item: popout.maskItem }
    // surfaceH stays at the largest panel height until close, preventing a
    // second layer-shell configure after a shorter morph. Tell Hyprland which
    // part actually has non-zero alpha so the transparent remainder does not
    // enlarge the compositor's blur pass.
    // The Quickshell 0.2.1 qmltypes omit this attached property's Region type.
    // qmllint disable missing-type
    HyprlandWindow.visibleMask: visualRegion
    // qmllint enable missing-type
    Region { id: visualRegion; item: popout.visualItem }

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "qs-bar-popout"

    HyprlandFocusGrab {
        active: root.live && Popouts.open
        windows: [root.bar, root]
        onCleared: {
            // Deactivating the old monitor host during a handoff is not an
            // outside click. The newly live host takes over the grab.
            if (root.live || !PanelRegistry.persistsAcrossHosts(Popouts.currentName))
                Popouts.close();
        }
    }

    PopoutHost {
        id: popout
        width: root.bar.width
        height: root.implicitHeight
        live: root.live
        outputAvailableHeight: root.screen ? root.screen.height : 560
        leftIslandRect: root.bar.leftIslandRect
        centerIslandRect: root.bar.centerIslandRect
        rightIslandRect: root.bar.rightIslandRect
    }
}
