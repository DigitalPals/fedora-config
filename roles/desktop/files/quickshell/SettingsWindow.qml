import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "Common"

// Shell settings window (design v2 "Shell settings"): a centered modal on
// the overlay layer. Same shell as LauncherWindow — scrim, focus grab,
// Escape — with a fixed-size surface dead-centered on the focused output.
// Hosts the shell-wide "settings" IPC target; like the launcher, this window
// is instantiated exactly once at ShellRoot, never per output.
PanelWindow {
    id: root

    visible: Settings.open
    screen: Settings.screen
    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-settings"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    HyprlandFocusGrab {
        active: Settings.open
        windows: [root]
        onCleared: Settings.closeWindow()
    }

    IpcHandler {
        target: "settings"

        function toggle(): void {
            Settings.toggleWindow();
        }

        function open(page: string): void {
            if (page !== "")
                Settings.page = page;
            if (!Settings.open)
                Settings.toggleWindow();
        }

        function close(): void {
            Settings.closeWindow();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(8 / 255, 9 / 255, 12 / 255, 0.5)
    }

    MouseArea {
        anchors.fill: parent
        onPressed: Settings.closeWindow()
    }

    FocusScope {
        id: stage
        anchors.fill: parent
        focus: true

        // A drag on the modules page grabs the first Escape; the second
        // closes the window (design v2 Esc behavior).
        Keys.onEscapePressed: {
            if (viewLoader.item && viewLoader.item.dragActive)
                viewLoader.item.cancelDrag();
            else
                Settings.closeWindow();
        }

        readonly property real targetW: viewLoader.item ? viewLoader.item.implicitWidth : 680
        readonly property real targetH: viewLoader.item ? viewLoader.item.implicitHeight : 516

        RectangularShadow {
            anchors.fill: surface
            radius: surface.radius
            blur: 48
            offset.y: 16
            color: Qt.rgba(0, 0, 0, 0.55)
        }

        ClippingRectangle {
            id: surface
            x: Math.round((root.width - stage.targetW) / 2)
            y: Math.round((root.height - stage.targetH) / 2)
            width: stage.targetW
            height: stage.targetH
            radius: Theme.popRadius
            color: Theme.popBg
            border.width: 1
            border.color: Theme.popBorder

            Loader {
                id: viewLoader
                anchors.fill: parent
                active: Settings.open
                focus: true
                source: active ? "Settings/SettingsView.qml" : ""
            }
        }
    }
}
