import QtQuick
import Quickshell.Hyprland
import "../Common"

Row {
    id: root
    spacing: 2
    anchors.verticalCenter: parent.verticalCenter

    readonly property int slots: Math.max(5, ...Hyprland.workspaces.values.map(w => w.id))

    Repeater {
        model: root.slots

        delegate: Item {
            required property int index
            readonly property int wsId: index + 1
            readonly property var ws: Hyprland.workspaces.values.find(w => w.id === wsId) ?? null
            readonly property bool exists: ws !== null
            readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === wsId
            readonly property bool urgent: exists && ws.urgent
            // Only workspaces that actually exist get a numbered chip;
            // empty slots stay compact dots.
            readonly property bool showNumber: exists

            width: showNumber ? (focused ? 28 : Theme.chipHeight) : 20
            height: Theme.chipHeight
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

                Text {
                    anchors.centerIn: parent
                    text: wsId
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.barTextSize
                    font.weight: parent.parent.focused || parent.parent.urgent ? Theme.weightSemibold : Theme.weightMedium
                    font.features: Theme.tabularNumberFeatures
                    color: parent.parent.focused ? Theme.accentFg : parent.parent.urgent ? Theme.redText : wsMouse.containsMouse ? Theme.textHi : Theme.textLow
                }
            }

            Rectangle {
                visible: !parent.showNumber
                anchors.centerIn: parent
                width: 4
                height: 4
                radius: 2
                color: parent.exists ? Theme.textLow : Theme.dotDim
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
