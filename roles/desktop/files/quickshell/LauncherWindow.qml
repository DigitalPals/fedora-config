import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "Common"

// Full-screen overlay hosting the launcher: a centred glass card that
// springs in over an undimmed desktop — the compositor blurs only the card
// itself — and any click outside it closes it.
PanelWindow {
    id: root

    // Kept mapped through the fade-out so the exit animation is visible.
    visible: Launcher.open || panel.opacity > 0.001
    screen: Launcher.screen
    anchors { top: true; left: true; right: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-launcher"
    WlrLayershell.keyboardFocus: Launcher.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

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

    MouseArea {
        anchors.fill: parent
        onPressed: Launcher.close()
    }

    FocusScope {
        id: stage
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: Launcher.close()

        // The card's top edge stays put while the result list grows and
        // shrinks; it sits where a fully populated launcher would centre
        // (search tile, eight rows, footer — about 520 logical pixels).
        readonly property real anchorY: Math.max(24, Math.round((root.height - 520) / 2))

        ClippingRectangle {
            id: panel

            x: Math.round((root.width - width) / 2)
            y: stage.anchorY
            width: launcherLoader.item ? launcherLoader.item.implicitWidth : 560
            height: launcherLoader.item ? launcherLoader.item.implicitHeight : 200
            radius: Theme.popRadius
            color: Theme.glassStrong

            // The transform springs while opacity eases, so the shape
            // arrives a beat after the content becomes legible.
            opacity: Launcher.open ? 1 : 0
            scale: Launcher.open ? 1 : 0.955

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.panelFadeDuration
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: Theme.panelMotionDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.springCurve
                }
            }

            // Results arriving or leaving roll the card open or closed. No
            // spring here: an overshoot past the content shows bare glass.
            Behavior on height {
                enabled: Launcher.open
                NumberAnimation {
                    duration: Theme.expandDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.easeOutCurve
                }
            }

            transform: Translate {
                y: Launcher.open ? 0 : -18

                Behavior on y {
                    NumberAnimation {
                        duration: Theme.panelMotionDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.springCurve
                    }
                }
            }

            Loader {
                id: launcherLoader
                // Stay warm after the first open so reopening is instant;
                // the view resets its own state on each open.
                property bool warm: false
                active: Launcher.open || warm
                focus: true
                source: active ? "LauncherView.qml" : ""
                onLoaded: {
                    warm = true;
                    item.drawBackground = false;
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: panel.radius
                color: "transparent"
                border.width: 1
                border.color: Theme.stroke
            }
        }
    }
}
