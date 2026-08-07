pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../Common"
import "../Common/ProcHelpers.js" as ProcHelpers
import "../Common/StatusHelpers.js" as StatusHelpers

Surface {
    id: root

    property string ipAddress: ""

    Process {
        id: ipProc
        // NetworkDevice.address is the (randomized) MAC, not the IPv4
        // address — checked against a live instance — so the address still
        // comes from `ip`. Argv form: no shell, so the device name cannot be
        // read as syntax, and no `jq` for a field JSON.parse already has.
        property string body: ""
        property string errText: ""
        property bool exitSeen: false
        property int lastExit: 0

        command: ["ip", "-j", "-4", "addr", "show", WifiState.device ? WifiState.device.name : ""]
        running: WifiState.device !== null

        stdout: StdioCollector {
            onStreamFinished: ipProc.body = text
        }
        stderr: StdioCollector {
            onStreamFinished: ipProc.errText = text
        }
        onExited: (exitCode, exitStatus) => {
            ipProc.exitSeen = true;
            ipProc.lastExit = exitCode;
        }
        onRunningChanged: {
            if (running) {
                body = "";
                errText = "";
                exitSeen = false;
                lastExit = 0;
                return;
            }
            const status = exitSeen ? lastExit : ProcHelpers.NOT_STARTED;
            root.ipAddress = status === 0 ? ProcHelpers.firstIpv4(body) : "";
            // The address is a detail line, so a failure stays out of the
            // popover — but it stops disappearing without a word.
            if (status !== 0)
                console.warn("wifi address lookup failed:", ProcHelpers.commandError("ip", status, errText));
        }
    }
    // The scan runs only while this view is alive; WifiState owns the
    // device, but the radio cost belongs to whoever is showing the list.
    Component.onCompleted: WifiState.setScanning(true)
    Component.onDestruction: WifiState.setScanning(false)

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
            checked: WifiState.enabled
            onToggled: v => WifiState.setEnabled(v)
        }
    }

    // Connected network
    Rectangle {
        visible: WifiState.connected
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
                    text: WifiState.name
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontBody
                    font.weight: Theme.weightMedium
                    color: Theme.textHi
                    elide: Text.ElideRight
                    width: parent.width
                }

                Text {
                    text: {
                        if (!WifiState.active)
                            return "";
                        let parts = ["Connected"];
                        const s = WifiState.signal;
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
        visible: !WifiState.enabled
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
        model: WifiState.others

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
                    opacity: 0.35 + 0.65 * Math.min(1, Math.max(0, StatusHelpers.signalPercent(net.modelData.signalStrength)) / 100)
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
        visible: WifiState.enabled
    }

    Item {
        visible: WifiState.enabled
        width: parent.width
        height: Theme.rowHeight

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: WifiState.scanning ? "Scanning…" : ""
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
