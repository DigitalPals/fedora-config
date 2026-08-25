pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../Common"
import "../Common/ProcHelpers.js" as ProcHelpers
import "../Common/StatusHelpers.js" as StatusHelpers

// Stable panel name and filename aside, this is the combined Network view:
// wired devices are informational and Wi-Fi keeps its radio and connection
// actions. `wifi` remains the persisted module and IPC identifier.
Surface {
    id: root

    implicitWidth: Theme.popWidth

    readonly property var networkSettingsCommand: ["sh", "-c",
        "command -v nm-connection-editor >/dev/null && exec nm-connection-editor || exec gnome-control-center network"]
    readonly property real bodyLimit: Math.max(240, availableHeight - padding * 2)

    property string ipAddress: ""

    Claim {
        active: root.visible
        onClaimed: EthernetState.acquire()
        onReleased: EthernetState.release()
    }

    Process {
        id: ipProc
        // NetworkDevice.address is the (randomized) MAC, not the IPv4
        // address, so Wi-Fi retains its small address lookup. Ethernet gets
        // the same value from the shared nmcli snapshot.
        property string body: ""
        property string errText: ""
        property bool exitSeen: false
        property int lastExit: 0

        command: ["ip", "-j", "-4", "addr", "show",
            WifiState.device ? WifiState.device.name : ""]
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
            if (status !== 0)
                console.warn("wifi address lookup failed:",
                    ProcHelpers.commandError("ip", status, errText));
        }
    }

    // Scanning is a live radio cost and belongs only to this visible detail
    // view. EthernetState's Claim follows the same lifetime.
    Component.onCompleted: WifiState.setScanning(true)
    Component.onDestruction: WifiState.setScanning(false)

    Item {
        id: viewport

        width: parent.width
        height: Math.min(networkContent.implicitHeight, root.bodyLimit)

        Flickable {
            id: networkFlick

            anchors.fill: parent
            contentWidth: width
            contentHeight: networkContent.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            clip: true
            flickDeceleration: 3000

            Column {
                id: networkContent

                width: networkFlick.width - 6
                spacing: 8

                Item {
                    width: parent.width
                    height: Theme.listRowHeight

                    Text {
                        x: 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Network"
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontBody
                        font.weight: Theme.weightSemibold
                        color: Theme.textHi
                    }

                    Sym {
                        anchors.right: parent.right
                        anchors.rightMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        name: EthernetState.connected ? "lan" : "wifi"
                        size: Theme.iconMedium
                        color: EthernetState.connected || WifiState.connected
                            ? Theme.accent : Theme.icon
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Theme.hairlineSoft
                    }
                }

                SectionLabel {
                    width: parent.width
                    text: "ETHERNET"
                }

                Text {
                    visible: !EthernetState.known
                    width: parent.width
                    topPadding: 10
                    bottomPadding: 12
                    text: "Checking Ethernet…"
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontSecondary
                    color: Theme.textDim
                }

                Column {
                    visible: EthernetState.error !== ""
                    width: parent.width
                    spacing: 3

                    Text {
                        width: parent.width
                        text: "Ethernet status unavailable"
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontSecondary
                        font.weight: Theme.weightMedium
                        color: Theme.textMid
                    }

                    Text {
                        width: parent.width - 20
                        x: 10
                        text: EthernetState.error
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontTiny
                        color: Theme.textDim
                    }
                }

                Text {
                    visible: EthernetState.known && EthernetState.error === ""
                        && EthernetState.devices.length === 0
                    width: parent.width
                    topPadding: 10
                    bottomPadding: 12
                    text: "No Ethernet ports"
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontSecondary
                    color: Theme.textDim
                }

                Repeater {
                    model: EthernetState.devices

                    delegate: Rectangle {
                        id: ethernetRow

                        required property var modelData

                        width: networkContent.width - 4
                        x: 2
                        height: Theme.panelTileHeight + 4
                        radius: Theme.rowRadius
                        color: modelData.connected ? Theme.chip : "transparent"

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 10
                            spacing: 10

                            Sym {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                horizontalAlignment: Text.AlignHCenter
                                name: "lan"
                                size: Theme.fontBody
                                fill: ethernetRow.modelData.connected ? 1 : 0
                                color: ethernetRow.modelData.connected
                                    ? Theme.accent : Theme.textDim
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: ethernetRow.width - 48
                                spacing: 1

                                Text {
                                    width: parent.width
                                    text: ethernetRow.modelData.connection !== ""
                                        ? ethernetRow.modelData.connection : "No active profile"
                                    font.family: Theme.fontMenu
                                    font.pixelSize: Theme.fontBody
                                    font.weight: ethernetRow.modelData.connected
                                        ? Theme.weightMedium : Theme.weightRegular
                                    color: ethernetRow.modelData.connected
                                        ? Theme.textHi : Theme.textMid
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: ethernetRow.modelData.device + " · "
                                        + ethernetRow.modelData.status
                                    font.family: Theme.fontMenu
                                    font.pixelSize: Theme.fontSecondary
                                    color: Theme.textLow
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: ethernetRow.modelData.ipv4 !== ""
                                    width: parent.width
                                    text: ethernetRow.modelData.ipv4
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontTiny
                                    color: Theme.textDim
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                HDivider {
                    width: parent.width
                }

                Item {
                    width: parent.width
                    height: Theme.listRowHeight

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
                        accessibleName: "Wi-Fi"
                        onToggled: value => WifiState.setEnabled(value)
                    }
                }

                Rectangle {
                    visible: WifiState.connected
                    width: parent.width - 4
                    x: 2
                    height: Theme.panelTileHeight
                    radius: Theme.rowRadius
                    color: Theme.chip

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 10
                        spacing: 10

                        Sym {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18
                            horizontalAlignment: Text.AlignHCenter
                            name: "wifi"
                            size: Theme.fontBody
                            color: Theme.accent
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: networkContent.width - 90
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
                                    const parts = ["Connected"];
                                    const signal = WifiState.signal;
                                    if (signal >= 0)
                                        parts.push(signal + "%");
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

                    Sym {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        name: "settings"
                        size: Theme.fontSecondary
                        color: gearMouse.containsMouse ? Theme.textHi : Theme.textDim

                        MouseArea {
                            id: gearMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Quickshell.execDetached(root.networkSettingsCommand);
                                Popouts.close();
                            }
                        }
                    }
                }

                Text {
                    visible: !WifiState.enabled || WifiState.device === null
                    width: parent.width
                    topPadding: 12
                    bottomPadding: 14
                    text: !WifiState.enabled ? "Wi-Fi is off" : "No Wi-Fi adapter"
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontSecondary
                    color: Theme.textDim
                }

                Repeater {
                    model: WifiState.others

                    delegate: Rectangle {
                        id: net

                        required property var modelData

                        width: networkContent.width - 4
                        x: 2
                        height: Theme.listRowHeight
                        radius: Theme.rowRadius
                        color: netMouse.containsMouse ? Theme.hoverFill : "transparent"

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 10
                            spacing: 10

                            Sym {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                horizontalAlignment: Text.AlignHCenter
                                name: "wifi"
                                size: Theme.fontBody
                                color: Theme.textMid
                                opacity: 0.35 + 0.65 * Math.min(1, Math.max(0,
                                    StatusHelpers.signalPercent(net.modelData.signalStrength)) / 100)
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: networkContent.width - 86
                                text: net.modelData.name
                                font.family: Theme.fontMenu
                                font.pixelSize: Theme.fontBody
                                color: Theme.textMid
                                elide: Text.ElideRight
                            }
                        }

                        Sym {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            visible: net.modelData.security !== WifiSecurityType.None
                            name: "lock"
                            size: Theme.fontCaption
                            color: Theme.textDim
                        }

                        MouseArea {
                            id: netMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: net.modelData.connect()
                        }
                    }
                }

                HDivider {
                    width: parent.width
                }

                Item {
                    width: parent.width
                    height: Theme.listRowHeight

                    Text {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: WifiState.enabled && WifiState.scanning ? "Scanning…" : ""
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontSecondary
                        color: Theme.textDim
                    }

                    LinkText {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Network settings"
                        onClicked: {
                            Quickshell.execDetached(root.networkSettingsCommand);
                            Popouts.close();
                        }
                    }
                }
            }
        }

        ScrollChrome {
            anchors.fill: parent
            target: networkFlick
        }
    }
}
