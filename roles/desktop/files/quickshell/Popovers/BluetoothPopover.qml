pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Bluetooth
import "../Common"

Surface {
    id: root

    readonly property var devices: BluetoothState.devices

    // Header + toggle
    Item {
        width: parent.width
        height: Theme.rowHeight

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Bluetooth"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontBody
            font.weight: Theme.weightSemibold
            color: Theme.textHi
        }

        Toggle {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            checked: BluetoothState.enabled
            accessibleName: "Bluetooth"
            onToggled: v => {
                BluetoothState.setEnabled(v);
            }
        }
    }

    Text {
        visible: !BluetoothState.enabled
        width: parent.width
        topPadding: 12
        bottomPadding: 14
        text: BluetoothState.adapter === null ? "No Bluetooth adapter" : "Bluetooth is off"
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontSecondary
        color: Theme.textDim
    }

    Text {
        visible: BluetoothState.enabled && root.devices.length === 0
        width: parent.width
        topPadding: 12
        bottomPadding: 14
        text: "No paired devices"
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontSecondary
        color: Theme.textDim
    }

    Repeater {
        model: root.devices

        delegate: Rectangle {
            id: dev

            required property var modelData
            readonly property bool busy: modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting

            width: parent.width - 4
            x: 2
            height: modelData.connected ? Theme.tileHeight : Theme.rowHeight
            radius: Theme.rowRadius
            color: modelData.connected ? Theme.accentBgSoft : btMouse.containsMouse ? Theme.hoverFill : "transparent"
            opacity: modelData.connected || btMouse.containsMouse ? 1 : 0.75

            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: 10
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    horizontalAlignment: Text.AlignHCenter
                    text: {
                        const icon = dev.modelData.icon || "";
                        if (icon.includes("headset") || icon.includes("headphone") || icon.includes("audio"))
                            return "\uf025";
                        if (icon.includes("input-gaming"))
                            return "\uf11b";
                        if (icon.includes("mouse"))
                            return "\uf245";
                        if (icon.includes("keyboard"))
                            return "\uf11c";
                        if (icon.includes("phone"))
                            return "\uf10b";
                        return "\uf293";
                    }
                    font.family: Theme.fontIcon
                    font.pixelSize: Theme.fontBody
                    color: dev.modelData.connected ? Theme.accent : Theme.textMid
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.width - 130
                    spacing: 1

                    Text {
                        width: parent.width
                        text: dev.modelData.deviceName
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontBody
                        font.weight: dev.modelData.connected ? Theme.weightMedium : Theme.weightRegular
                        color: dev.modelData.connected ? Theme.textHi : Theme.textMid
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: dev.modelData.connected
                        width: parent.width
                        text: "Connected" + (dev.modelData.batteryAvailable ? " · " + Math.round(dev.modelData.battery * 100) + "%" : "")
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontSecondary
                        color: Theme.textLow
                    }
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: dev.busy ? "…" : dev.modelData.connected ? "Disconnect" : dev.modelData.paired ? "Paired" : "Not connected"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontSecondary
                font.weight: dev.modelData.connected ? Theme.weightMedium : Theme.weightRegular
                color: dev.modelData.connected ? (actionMouse.containsMouse ? Theme.red : Theme.textDim) : Theme.textDim

                MouseArea {
                    id: actionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: dev.modelData.connected
                    onClicked: dev.modelData.disconnect()
                }
            }

            MouseArea {
                id: btMouse
                anchors.fill: parent
                hoverEnabled: true
                z: -1
                onClicked: {
                    if (!dev.modelData.connected && !dev.busy)
                        dev.modelData.connect();
                }
            }
        }
    }
}
