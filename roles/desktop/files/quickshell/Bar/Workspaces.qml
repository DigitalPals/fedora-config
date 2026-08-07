pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import "../Common"

Row {
    id: root

    // Only to hand the bar's pointer state to the tooltips below.
    property Bar host: null

    spacing: 2
    anchors.verticalCenter: parent.verticalCenter

    readonly property int slots: Math.max(Settings.modOpts.ws.minSlots,
        ...Hyprland.workspaces.values.map(w => w.id))

    Repeater {
        model: root.slots

        delegate: Item {
            id: slot

            required property int index
            readonly property int wsId: index + 1
            readonly property var ws: Hyprland.workspaces.values.find(w => w.id === wsId) ?? null
            readonly property bool exists: ws !== null
            readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === wsId
            readonly property bool urgent: exists && ws.urgent
            readonly property bool hidden: Settings.modOpts.ws.hideEmpty && !exists && !focused
            // Only workspaces that actually exist get a numbered chip;
            // empty slots stay compact dots. Dots style keeps everything
            // a dot, with the focused workspace picked out in accent.
            readonly property bool showNumber: exists && Settings.modOpts.ws.style === "numbers"

            visible: !hidden
            width: hidden ? 0 : showNumber ? (focused ? 28 : Theme.chipHeight) : 20
            height: Theme.chipHeight

            Behavior on width {
                NumberAnimation { duration: Theme.chipFadeDuration; easing.type: Easing.OutCubic }
            }
            anchors.verticalCenter: parent.verticalCenter
            Accessible.role: Accessible.Button
            Accessible.name: "Workspace " + wsId
                + (focused ? ", current" : urgent ? ", urgent" : exists ? "" : ", empty")
            Accessible.onPressAction: Hyprland.dispatch(
                "hl.dsp.focus({ workspace = " + wsId + " })")

            Rectangle {
                visible: slot.showNumber
                anchors.fill: parent
                radius: Theme.chipRadius
                color: slot.focused ? Theme.accent : slot.urgent ? Theme.redBg : wsMouse.containsMouse ? Theme.hoverFill : "transparent"

                Behavior on color {
                    ColorAnimation { duration: Theme.chipFadeDuration }
                }

                Text {
                    anchors.centerIn: parent
                    text: slot.wsId
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.barTextSize
                    font.weight: slot.focused || slot.urgent ? Theme.weightSemibold : Theme.weightMedium
                    font.features: Theme.tabularNumberFeatures
                    color: slot.focused ? Theme.accentFg : slot.urgent ? Theme.redText : wsMouse.containsMouse ? Theme.textHi : Theme.textLow

                    Behavior on color {
                        ColorAnimation { duration: Theme.chipFadeDuration }
                    }
                }
            }

            Rectangle {
                visible: !slot.showNumber
                anchors.centerIn: parent
                width: slot.focused ? 6 : 4
                height: width
                radius: width / 2
                color: slot.focused ? Theme.accent
                    : slot.urgent ? Theme.red
                    : slot.exists ? Theme.textLow : Theme.dotDim
            }

            MouseArea {
                id: wsMouse
                anchors.fill: parent
                hoverEnabled: true
                // This Hyprland build speaks the Lua IPC dialect: raw
                // dispatch text is evaluated as `hl.dispatch(<text>)`.
                onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + slot.wsId + " })")
            }

            BarTooltip {
                host: root.host
                hovered: wsMouse.containsMouse
                text: "Workspace " + slot.wsId
                    + (slot.focused ? " · current" : slot.urgent ? " · urgent" : slot.exists ? "" : " · empty")
                y: slot.height + 6
                x: (slot.width - width) / 2
            }
        }
    }
}
