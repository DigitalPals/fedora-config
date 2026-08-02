import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "Common"

PanelWindow {
    id: root

    visible: Launcher.open
    screen: Launcher.screen
    anchors { top: true; left: true; right: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-launcher"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    HyprlandFocusGrab {
        active: Launcher.open
        windows: [root]
        onCleared: Launcher.close()
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            Launcher.toggle();
        }

        function close(): void {
            Launcher.close();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(8 / 255, 9 / 255, 12 / 255, 0.5)
    }

    MouseArea {
        anchors.fill: parent
        onPressed: Launcher.close()
    }

    FocusScope {
        id: stage
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: Launcher.close()

        readonly property real targetW: launcherLoader.item ? launcherLoader.item.implicitWidth : 600
        readonly property real targetH: launcherLoader.item ? launcherLoader.item.implicitHeight : 200
        readonly property real targetX: Math.round((root.width - targetW) / 2)
        readonly property real targetY: Math.round(root.height * 0.16)

        RectangularShadow {
            anchors.fill: surface
            radius: surface.radius
            blur: 48
            offset.y: 16
            color: Qt.rgba(0, 0, 0, 0.55)
        }

        ClippingRectangle {
            id: surface
            x: stage.targetX
            y: stage.targetY
            width: stage.targetW
            height: stage.targetH
            radius: Theme.popRadius
            color: Theme.popBg

            Item {
                x: 0
                y: 0
                width: stage.targetW
                height: stage.targetH

                Loader {
                    id: launcherLoader
                    active: Launcher.open
                    focus: true
                    source: active ? "LauncherView.qml" : ""
                    onLoaded: item.drawBackground = false
                }
            }
        }
    }
}
