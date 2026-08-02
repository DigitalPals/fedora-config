import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "../Common"

// Fullscreen overlay for the centered SUPER+SPACE launcher (design 4a):
// summoned over a dimmed desktop, morphing open from a slightly smaller
// centered rect. Every other view is a connected island popout fused to
// the bar (design t5) and lives in the bar window instead.
PanelWindow {
    id: root

    visible: Popovers.current !== ""

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-popover"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // External control, e.g. `qs ipc call popovers toggle launcher` bound
    // to SUPER+SPACE in Hyprland. Legacy popover names route to the
    // connected island popouts.
    IpcHandler {
        target: "popovers"

        function toggle(name: string): void {
            if (name === "launcher")
                Popovers.toggle(name, 0, 0);
            else
                Popouts.toggle(name);
        }

        function close(): void {
            Popovers.close();
            Popouts.close();
        }
    }

    // Replay the open animation whenever the launcher opens; play the
    // exit animation when a close is requested.
    Connections {
        target: Popovers

        function onCurrentChanged() {
            if (Popovers.current !== "") {
                closeAnim.stop();
                stage.prog = 0;
                openAnim.restart();
            }
        }

        function onClosingChanged() {
            if (Popovers.closing) {
                openAnim.stop();
                closeAnim.restart();
            }
        }
    }

    NumberAnimation {
        id: openAnim
        target: stage
        property: "prog"
        to: 1
        duration: Theme.animOpen
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curveSpatial
    }

    NumberAnimation {
        id: closeAnim
        target: stage
        property: "prog"
        to: 0
        duration: Theme.animClose
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curveAccel
        onFinished: Popovers.finishClose()
    }

    // Dimmed desktop behind the centered launcher
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(8 / 255, 9 / 255, 12 / 255, 0.5)
        opacity: stage.prog
        visible: opacity > 0
    }

    MouseArea {
        anchors.fill: parent
        onPressed: Popovers.close()
    }

    FocusScope {
        id: stage
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: Popovers.close()

        // 0 = tucked into the origin, 1 = fully open
        property real prog: 0

        readonly property real targetW: loader.item ? loader.item.width : Theme.popWidth
        readonly property real targetH: loader.item ? loader.item.height : 200
        readonly property real targetX: Math.round((root.width - targetW) / 2)
        readonly property real targetY: Math.round(root.height * 0.16)

        function lp(a, b) {
            return a + (b - a) * prog;
        }

        RectangularShadow {
            anchors.fill: morphBg
            radius: morphBg.radius
            blur: 48
            spread: 0
            offset.y: 16
            color: Qt.rgba(0, 0, 0, 0.55 * stage.prog)
        }

        // The morphing surface: clips its content, so the launcher is
        // revealed as the surface expands into place.
        ClippingRectangle {
            id: morphBg
            visible: Popovers.current !== ""
            x: stage.lp(stage.targetX + stage.targetW * 0.07, stage.targetX)
            y: stage.lp(stage.targetY + 16 + stage.targetH * 0.07, stage.targetY)
            width: Math.max(1, stage.lp(stage.targetW * 0.86, stage.targetW))
            height: Math.max(1, stage.lp(stage.targetH * 0.86, stage.targetH))
            radius: Theme.popRadius
            color: Theme.popBg

            // Content pinned at its final on-screen position inside the
            // moving clip.
            Item {
                x: stage.targetX - morphBg.x
                y: stage.targetY - morphBg.y
                width: stage.targetW
                height: stage.targetH
                opacity: stage.prog

                Loader {
                    id: loader
                    active: Popovers.current !== ""
                    focus: true
                    source: active ? "LauncherPopover.qml" : ""

                    // The morph surface draws the background.
                    onLoaded: {
                        if (item.drawBackground !== undefined)
                            item.drawBackground = false;
                    }
                }
            }
        }
    }
}
