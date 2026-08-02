import QtQuick
import Quickshell
import Quickshell.Io
import "../Common"

// Tailscale detail view: tailnet status, this machine, and the peer
// list from `tailscale status --json`. Clicking a peer copies its
// Tailscale IP.
Surface {
    id: root

    property var peers: []
    property bool statusKnown: false
    property string copiedIp: ""

    function refresh() {
        statusProc.running = false;
        statusProc.running = true;
    }

    function copyIp(ip) {
        if (ip === "")
            return;
        Quickshell.execDetached(["wl-copy", ip]);
        copiedIp = ip;
        copiedReset.restart();
    }

    Timer {
        id: copiedReset
        interval: 1600
        onTriggered: root.copiedIp = ""
    }

    Process {
        id: statusProc
        command: ["tailscale", "status", "--json"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(text);
                    const list = Object.values(s.Peer ?? {}).map(p => ({
                        name: (p.DNSName || p.HostName || "?").split(".")[0],
                        online: !!p.Online,
                        ip: p.TailscaleIPs && p.TailscaleIPs[0] || "",
                        os: p.OS || "",
                        exitOption: !!p.ExitNodeOption,
                        exit: !!p.ExitNode
                    }));
                    list.sort((a, b) => (b.online - a.online) || a.name.localeCompare(b.name));
                    root.peers = list;
                } catch (e) {
                    root.peers = [];
                }
                root.statusKnown = true;
            }
        }
    }

    Timer {
        id: toggleRefresh
        interval: 1400
        onTriggered: {
            SysInfo.refreshTailscale();
            root.refresh();
        }
    }

    // Header + toggle
    Item {
        width: parent.width
        height: 36

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Tailscale"
            font.family: Theme.fontSans
            font.pixelSize: 12
            font.weight: 600
            color: Theme.textHi
        }

        Toggle {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            checked: SysInfo.tsRunning
            onToggled: v => {
                Quickshell.execDetached(["sh", "-c", v ? "tailscale up" : "tailscale down"]);
                toggleRefresh.restart();
            }
        }
    }

    // This machine
    Rectangle {
        visible: SysInfo.tsRunning
        width: parent.width - 4
        x: 2
        height: 52
        radius: Theme.rowRadius
        color: Theme.accentBgSoft

        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 10
            spacing: 10

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18

                Image {
                    anchors.centerIn: parent
                    width: 13
                    height: 13
                    sourceSize: Qt.size(26, 26)
                    source: Quickshell.shellDir + "/assets/tailscale.svg"
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: root.width - 90
                spacing: 1

                Text {
                    width: parent.width
                    text: SysInfo.tsHost + (SysInfo.tsNet !== "" ? " · " + SysInfo.tsNet : "")
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight: 500
                    color: Theme.textHi
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.copiedIp === SysInfo.tsIp && SysInfo.tsIp !== ""
                        ? "Copied " + SysInfo.tsIp
                        : "Connected · " + SysInfo.tsIp + (SysInfo.tsExitNode ? " · exit node active" : "")
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    color: root.copiedIp === SysInfo.tsIp && SysInfo.tsIp !== "" ? Theme.accent : Theme.textLow
                    elide: Text.ElideRight
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.copyIp(SysInfo.tsIp)
        }
    }

    // Off / loading states
    Text {
        visible: !SysInfo.tsRunning
        width: parent.width
        topPadding: 14
        bottomPadding: 14
        text: "Tailscale is stopped"
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontSans
        font.pixelSize: 11
        color: Theme.textDim
    }

    Text {
        visible: SysInfo.tsRunning && !root.statusKnown
        width: parent.width
        topPadding: 10
        bottomPadding: 10
        text: "Loading peers…"
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontSans
        font.pixelSize: 11
        color: Theme.textDim
    }

    // Peers
    Repeater {
        model: SysInfo.tsRunning ? root.peers.slice(0, 8) : []

        delegate: Rectangle {
            id: peerRow

            required property var modelData

            width: parent.width - 4
            x: 2
            height: 34
            radius: Theme.rowRadius
            color: peerMouse.containsMouse ? Theme.hoverFill : "transparent"
            opacity: modelData.online || peerMouse.containsMouse ? 1 : 0.55

            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: 10
                spacing: 10

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7
                    height: 7
                    radius: 4
                    color: peerRow.modelData.online ? Theme.accent : Theme.dotDim
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: peerRow.modelData.name
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight: peerRow.modelData.online ? 500 : 400
                    color: peerRow.modelData.online ? Theme.textHi : Theme.textMid
                }

                Text {
                    visible: peerRow.modelData.os !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: peerRow.modelData.os
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    color: Theme.textDim
                }

                Rectangle {
                    visible: peerRow.modelData.exit || peerRow.modelData.exitOption
                    anchors.verticalCenter: parent.verticalCenter
                    width: exitText.implicitWidth + 10
                    height: 14
                    radius: 4
                    color: peerRow.modelData.exit ? Theme.accentBgSoft : Theme.hoverFill

                    Text {
                        id: exitText
                        anchors.centerIn: parent
                        text: peerRow.modelData.exit ? "EXIT" : "exit node"
                        font.family: Theme.fontSans
                        font.pixelSize: 9
                        font.weight: 600
                        font.letterSpacing: 0.5
                        color: peerRow.modelData.exit ? Theme.accent : Theme.textDim
                    }
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: root.copiedIp !== "" && root.copiedIp === peerRow.modelData.ip ? "copied" : peerRow.modelData.ip
                font.family: Theme.fontMono
                font.pixelSize: 10
                color: root.copiedIp !== "" && root.copiedIp === peerRow.modelData.ip ? Theme.accent : Theme.textDim
            }

            MouseArea {
                id: peerMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.copyIp(peerRow.modelData.ip)
            }
        }
    }

    HDivider {
        visible: SysInfo.tsRunning
    }

    // Footer
    Item {
        width: parent.width
        height: 26

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: {
                if (!SysInfo.tsRunning || !root.statusKnown)
                    return "click a device to copy its IP";
                const online = root.peers.filter(p => p.online).length;
                return online + " of " + root.peers.length + " devices online · click to copy IP";
            }
            font.family: Theme.fontSans
            font.pixelSize: 11
            color: Theme.textDim
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Admin console"
            font.family: Theme.fontSans
            font.pixelSize: 11
            font.weight: 500
            color: adminMouse.containsMouse ? "#c8e2f4" : Theme.accent

            MouseArea {
                id: adminMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    Quickshell.execDetached(["xdg-open", "https://login.tailscale.com/admin/machines"]);
                    Popouts.close();
                }
            }
        }
    }
}
