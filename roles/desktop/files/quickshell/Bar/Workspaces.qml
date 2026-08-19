pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell.Hyprland
import "../Common"

// The workspace pager: a pill of pips, the focused one stretched into a lozenge
// and lit with the accent.
//
// The stretch is the whole idea — the focused workspace is not a differently
// coloured dot, it is a wider one, so the pager reads at a glance from the far
// side of the screen. Width springs; colour and glow cross-fade.
Rectangle {
    id: root

    // Only to hand the bar's pointer state to the tooltips below.
    property Bar host: null

    readonly property bool numbered: Settings.modOpts.ws.style === "numbers"
    readonly property int slots: Math.max(Settings.modOpts.ws.minSlots,
        ...Hyprland.workspaces.values.map(w => w.id))

    implicitWidth: pips.implicitWidth + 24
    implicitHeight: 30
    radius: Theme.pillRadius
    color: Theme.barChip
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    Behavior on color {
        ColorAnimation { duration: Theme.surfaceDuration }
    }

    Behavior on implicitWidth {
        enabled: root.host !== null && root.host.animationsReady
        NumberAnimation {
            duration: Theme.expandDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.springCurve
        }
    }

    Row {
        id: pips
        anchors.centerIn: parent
        spacing: 7

        Repeater {
            model: root.slots

            delegate: Item {
                id: slot

                required property int index
                readonly property int wsId: index + 1
                readonly property var ws: Hyprland.workspaces.values.find(w => w.id === wsId) ?? null
                readonly property bool exists: ws !== null
                readonly property bool focused: Hyprland.focusedWorkspace !== null
                    && Hyprland.focusedWorkspace.id === wsId
                readonly property bool urgent: exists && ws.urgent
                readonly property bool hidden: Settings.modOpts.ws.hideEmpty
                    && !exists && !focused
                readonly property color tone: focused ? Theme.barAccent
                    : urgent ? Theme.barRed
                    : root.numbered ? (exists ? Theme.barChipHover : Theme.barChip)
                    : exists ? Theme.barWsOccupied : Theme.barDotDim

                visible: !hidden
                width: hidden ? 0
                    : root.numbered ? (focused ? 26 : 18)
                    : (focused ? 30 : 10)
                height: root.numbered ? 18 : 10
                anchors.verticalCenter: parent.verticalCenter

                Behavior on width {
                    NumberAnimation {
                        duration: Theme.expandDuration + 50
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.springCurve
                    }
                }

                Behavior on height {
                    NumberAnimation { duration: Theme.chipFadeDuration + 100 }
                }

                Accessible.role: Accessible.Button
                Accessible.name: "Workspace " + wsId
                    + (focused ? ", current" : urgent ? ", urgent"
                        : exists ? ", occupied" : ", empty")
                Accessible.onPressAction: Hyprland.dispatch(
                    "hl.dsp.focus({ workspace = " + wsId + " })")

                // The focused pip carries a soft bloom of its own colour, which
                // is what stops the accent lozenge reading as a flat sticker.
                RectangularShadow {
                    anchors.fill: pip
                    radius: pip.radius
                    blur: 10
                    spread: 0
                    color: slot.focused ? Theme.barAccentGlow : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: Theme.chipFadeDuration }
                    }
                }

                Rectangle {
                    id: pip
                    anchors.fill: parent
                    radius: Theme.pillRadius
                    color: slot.tone
                    // Pips answer a press before the compositor has switched,
                    // and grow a little under the pointer so an eight-pixel
                    // target still feels like one.
                    scale: wsMouse.pressed ? 0.86
                        : wsPointer.over ? (root.numbered ? 1.12 : 1.18) : 1

                    Behavior on color {
                        ColorAnimation { duration: Theme.chipFadeDuration }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: Theme.pressDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.springCurve
                        }
                    }

                    Text {
                        visible: root.numbered
                        anchors.centerIn: parent
                        text: slot.wsId
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontMicro
                        font.weight: Theme.weightHeavy
                        font.features: Theme.tabularNumberFeatures
                        color: slot.focused ? Theme.barAccentFg
                            : slot.urgent ? Theme.barRedFg
                            : slot.exists ? Theme.barTextMid : Theme.barTextFaint

                        Behavior on color {
                            ColorAnimation { duration: Theme.chipFadeDuration }
                        }
                    }
                }

                PointerCheck {
                    id: wsPointer
                    host: root.host
                    target: slot
                    hovered: wsMouse.containsMouse
                }

                MouseArea {
                    id: wsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // This Hyprland build speaks the Lua IPC dialect: raw
                    // dispatch text is evaluated as `hl.dispatch(<text>)`.
                    onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + slot.wsId + " })")
                }

                BarTooltip {
                    check: wsPointer
                    text: "Workspace " + slot.wsId
                        + (slot.focused ? " · current" : slot.urgent ? " · urgent"
                            : slot.exists ? " · occupied" : " · empty")
                    y: root.height + 12
                    x: (slot.width - width) / 2
                }
            }
        }
    }
}
