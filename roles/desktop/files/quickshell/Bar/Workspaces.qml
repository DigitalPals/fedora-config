import QtQuick
import Quickshell.Hyprland
import "../Common"

Row {
    id: root
    spacing: 2
    anchors.verticalCenter: parent.verticalCenter

    readonly property int slots: Math.max(Settings.modOpts.ws.minSlots,
        ...Hyprland.workspaces.values.map(w => w.id))

    Repeater {
        model: root.slots

        delegate: Item {
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
                visible: parent.showNumber
                anchors.fill: parent
                radius: Theme.chipRadius
                color: parent.focused ? Theme.accent : parent.urgent ? Theme.redBg : wsMouse.containsMouse ? Theme.hoverFill : "transparent"

                Behavior on color {
                    ColorAnimation { duration: Theme.chipFadeDuration }
                }

                Text {
                    anchors.centerIn: parent
                    text: wsId
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.barTextSize
                    font.weight: parent.parent.focused || parent.parent.urgent ? Theme.weightSemibold : Theme.weightMedium
                    font.features: Theme.tabularNumberFeatures
                    color: parent.parent.focused ? Theme.accentFg : parent.parent.urgent ? Theme.redText : wsMouse.containsMouse ? Theme.textHi : Theme.textLow

                    Behavior on color {
                        ColorAnimation { duration: Theme.chipFadeDuration }
                    }
                }
            }

            Rectangle {
                visible: !parent.showNumber
                anchors.centerIn: parent
                width: parent.focused ? 6 : 4
                height: width
                radius: width / 2
                color: parent.focused ? Theme.accent
                    : parent.urgent ? Theme.red
                    : parent.exists ? Theme.textLow : Theme.dotDim
            }

            MouseArea {
                id: wsMouse
                anchors.fill: parent
                hoverEnabled: true
                // This Hyprland build speaks the Lua IPC dialect: raw
                // dispatch text is evaluated as `hl.dispatch(<text>)`.
                onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + parent.wsId + " })")
            }

            BarTooltip {
                hovered: wsMouse.containsMouse
                text: "Workspace " + wsId
                    + (focused ? " · current" : urgent ? " · urgent" : exists ? "" : " · empty")
                y: parent.height + 6
                x: (parent.width - width) / 2
            }
        }
    }
}
