import QtQuick
import Quickshell.Bluetooth
import "../Common"

Surface {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: {
        if (!adapter || !adapter.enabled)
            return [];
        return Bluetooth.devices.values
            .filter(d => d.paired || d.connected)
            .sort((a, b) => (b.connected - a.connected) || a.deviceName.localeCompare(b.deviceName));
    }

    // Header + toggle
    Item {
        width: parent.width
        height: 36

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Bluetooth"
            font.family: Theme.fontSans
            font.pixelSize: 12
            font.weight: 600
            color: Theme.textHi
        }

        Toggle {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            checked: root.adapter !== null && root.adapter.enabled
            onToggled: v => {
                if (root.adapter)
                    root.adapter.enabled = v;
            }
        }
    }

    Text {
        visible: root.adapter === null || !root.adapter.enabled
        width: parent.width
        topPadding: 12
        bottomPadding: 14
        text: root.adapter === null ? "No Bluetooth adapter" : "Bluetooth is off"
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontSans
        font.pixelSize: 11
        color: Theme.textDim
    }

    Text {
        visible: root.adapter !== null && root.adapter.enabled && root.devices.length === 0
        width: parent.width
        topPadding: 12
        bottomPadding: 14
        text: "No paired devices"
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontSans
        font.pixelSize: 11
        color: Theme.textDim
    }

    Repeater {
        model: root.devices

        delegate: Rectangle {
            required property var modelData
            readonly property bool busy: modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting

            width: parent.width - 4
            x: 2
            height: modelData.connected ? 52 : 38
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
                        const icon = modelData.icon || "";
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
                    font.pixelSize: 13
                    color: modelData.connected ? Theme.accent : Theme.textMid
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.width - 130
                    spacing: 1

                    Text {
                        width: parent.width
                        text: modelData.deviceName
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                        font.weight: modelData.connected ? 500 : 400
                        color: modelData.connected ? Theme.textHi : Theme.textMid
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: modelData.connected
                        width: parent.width
                        text: "Connected" + (modelData.batteryAvailable ? " · " + Math.round(modelData.battery * 100) + "%" : "")
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        color: Theme.textLow
                    }
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: busy ? "…" : modelData.connected ? "Disconnect" : modelData.paired ? "Paired" : "Not connected"
                font.family: Theme.fontSans
                font.pixelSize: 11
                font.weight: modelData.connected ? 500 : 400
                color: modelData.connected ? (actionMouse.containsMouse ? Theme.red : Theme.textDim) : Theme.textDim

                MouseArea {
                    id: actionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: modelData.connected
                    onClicked: modelData.disconnect()
                }
            }

            MouseArea {
                id: btMouse
                anchors.fill: parent
                hoverEnabled: true
                z: -1
                onClicked: {
                    if (!modelData.connected && !busy)
                        modelData.connect();
                }
            }
        }
    }
}
