pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../Common"

Surface {
    id: root

    readonly property var device: Networking.devices.values.find(d => d.networks !== undefined) ?? null
    property string ipAddress: ""

    // signalStrength arrives 0..1 in this backend; keep 0..100 inputs working.
    function pct(strength) {
        if (strength === undefined || strength === null)
            return -1;
        return Math.round(strength <= 1 ? strength * 100 : strength);
    }

    Process {
        id: ipProc
        command: ["sh", "-c", "ip -j -4 addr show " + (root.device ? root.device.name : "") + " 2>/dev/null | jq -r '.[0].addr_info[0].local // empty'"]
        running: root.device !== null
        stdout: StdioCollector {
            onStreamFinished: root.ipAddress = text.trim()
        }
    }
    readonly property var active: device ? (device.networks.values.find(n => n.connected) ?? null) : null
    readonly property var others: {
        if (!device || !Networking.wifiEnabled)
            return [];
        const seen = new Set();
        return device.networks.values
            .filter(n => !n.connected && n.name && n.name !== "")
            .sort((a, b) => b.signalStrength - a.signalStrength)
            .filter(n => {
                if (seen.has(n.name))
                    return false;
                seen.add(n.name);
                return true;
            })
            .slice(0, 7);
    }

    Component.onCompleted: {
        if (device && device.scannerEnabled !== undefined)
            device.scannerEnabled = true;
    }
    Component.onDestruction: {
        if (device && device.scannerEnabled !== undefined)
            device.scannerEnabled = false;
    }

    // Header + toggle
    Item {
        width: parent.width
        height: Theme.rowHeight

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Wi-Fi"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontBody
            font.weight: Theme.weightSemibold
            color: Theme.textHi
        }

        Toggle {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            checked: Networking.wifiEnabled
            onToggled: v => Networking.wifiEnabled = v
        }
    }

    // Connected network
    Rectangle {
        visible: root.active !== null
        width: parent.width - 4
        x: 2
        height: Theme.tileHeight
        radius: Theme.rowRadius
        color: Theme.accentBgSoft

        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 10
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                horizontalAlignment: Text.AlignHCenter
                text: "\uf1eb"
                font.family: Theme.fontIcon
                font.pixelSize: Theme.fontBody
                color: Theme.accent
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: root.width - 90
                spacing: 1

                Text {
                    text: root.active ? root.active.name : ""
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontBody
                    font.weight: Theme.weightMedium
                    color: Theme.textHi
                    elide: Text.ElideRight
                    width: parent.width
                }

                Text {
                    text: {
                        if (!root.active)
                            return "";
                        let parts = ["Connected"];
                        const s = root.pct(root.active.signalStrength);
                        if (s >= 0)
                            parts.push(s + "%");
                        if (root.ipAddress !== "")
                            parts.push(root.ipAddress);
                        return parts.join(" · ");
                    }
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontSecondary
                    color: Theme.textLow
                    elide: Text.ElideRight
                    width: parent.width
                }
            }
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "\uf013"
            font.family: Theme.fontIcon
            font.pixelSize: Theme.fontSecondary
            color: gearMouse.containsMouse ? Theme.textHi : Theme.textDim

            MouseArea {
                id: gearMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    Quickshell.execDetached(["sh", "-c", "command -v nm-connection-editor >/dev/null && exec nm-connection-editor || exec gnome-control-center wifi"]);
                    Popouts.close();
                }
            }
        }
    }

    // Wi-Fi off state
    Text {
        visible: !Networking.wifiEnabled
        width: parent.width
        topPadding: 14
        bottomPadding: 14
        text: "Wi-Fi is off"
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontSecondary
        color: Theme.textDim
    }

    // Other networks
    Repeater {
        model: root.others

        delegate: Rectangle {
            id: net

            required property var modelData

            width: parent.width - 4
            x: 2
            height: Theme.rowHeight
            radius: Theme.rowRadius
            color: netMouse.containsMouse ? Theme.hoverFill : "transparent"

            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: 10
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    horizontalAlignment: Text.AlignHCenter
                    text: "\uf1eb"
                    font.family: Theme.fontIcon
                    font.pixelSize: Theme.fontBody
                    color: Theme.textMid
                    opacity: 0.35 + 0.65 * Math.min(1, Math.max(0, root.pct(net.modelData.signalStrength)) / 100)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.width - 86
                    text: net.modelData.name
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontBody
                    color: Theme.textMid
                    elide: Text.ElideRight
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                visible: net.modelData.security !== WifiSecurityType.None
                text: "\uf023"
                font.family: Theme.fontIcon
                font.pixelSize: Theme.fontCaption
                color: Theme.textDim
            }

            MouseArea {
                id: netMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: net.modelData.connect()
            }
        }
    }

    HDivider {
        visible: Networking.wifiEnabled
    }

    Item {
        visible: Networking.wifiEnabled
        width: parent.width
        height: Theme.rowHeight

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: root.device && root.device.scannerEnabled ? "Scanning…" : ""
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontSecondary
            color: Theme.textDim
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Network settings"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontSecondary
            font.weight: Theme.weightMedium
            color: settingsMouse.containsMouse ? "#c8e2f4" : Theme.accent

            MouseArea {
                id: settingsMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    Quickshell.execDetached(["sh", "-c", "command -v nm-connection-editor >/dev/null && exec nm-connection-editor || exec gnome-control-center wifi"]);
                    Popouts.close();
                }
            }
        }
    }
}
