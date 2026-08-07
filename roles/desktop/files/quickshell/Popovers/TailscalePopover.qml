pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../Common"
import "../Common/ProcHelpers.js" as ProcHelpers

// Tailscale detail view: tailnet status, this machine, and the peer
// list from `tailscale status --json`. Clicking a peer copies its
// Tailscale IP.
Surface {
    id: root

    property var peers: []
    // A status run has come back, either way. An empty `peers` with no
    // statusError is a genuinely empty tailnet; a failed run says so
    // instead of counting to zero.
    property bool statusKnown: false
    property string statusError: ""
    property string copiedIp: ""

    function refresh() {
        statusProc.staleRuns += statusProc.running ? 1 : 0;
        statusProc.running = false;
        statusProc.running = true;
    }

    function settle(exitCode, body, errText) {
        statusKnown = true;
        const list = exitCode === 0 ? ProcHelpers.tailscalePeers(body) : null;
        if (list !== null) {
            peers = list;
            statusError = "";
            return;
        }
        peers = [];
        statusError = exitCode === 0
            ? "tailscale status returned output this shell could not read"
            : ProcHelpers.commandError("tailscale status", exitCode, errText);
        console.warn("tailscale peers unavailable:", statusError);
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
        // `tailscale status --json` writes its complaint to stderr and exits
        // nonzero when tailscaled is unreachable; both streams close before
        // exited(), and the falling edge of `running` is the only signal
        // there is when the binary cannot be launched at all.
        //
        // Runs killed by refresh() have yet to report in: their exit lands as
        // a crash some time after the replacement started, and is not news.
        property int staleRuns: 0
        property string body: ""
        property string errText: ""
        property bool exitSeen: false
        property int lastExit: 0

        command: ["tailscale", "status", "--json"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: statusProc.body = text
        }
        stderr: StdioCollector {
            onStreamFinished: statusProc.errText = text
        }
        onExited: (exitCode, exitStatus) => {
            statusProc.exitSeen = true;
            statusProc.lastExit = exitCode;
        }
        onRunningChanged: {
            if (running) {
                body = "";
                errText = "";
                exitSeen = false;
                lastExit = 0;
            } else if (staleRuns > 0) {
                staleRuns--;
            } else {
                root.settle(exitSeen ? lastExit : ProcHelpers.NOT_STARTED, body, errText);
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
        height: Theme.rowHeight

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Tailscale"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontBody
            font.weight: Theme.weightSemibold
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
        height: Theme.tileHeight
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
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontBody
                    font.weight: Theme.weightMedium
                    color: Theme.textHi
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.copiedIp === SysInfo.tsIp && SysInfo.tsIp !== ""
                        ? "Copied " + SysInfo.tsIp
                        : "Connected · " + SysInfo.tsIp + (SysInfo.tsExitNode ? " · exit node active" : "")
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontSecondary
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
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontSecondary
        color: Theme.textDim
    }

    Text {
        visible: SysInfo.tsRunning && !root.statusKnown
        width: parent.width
        topPadding: 10
        bottomPadding: 10
        text: "Loading peers…"
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontSecondary
        color: Theme.textDim
    }

    Text {
        visible: SysInfo.tsRunning && root.statusError !== ""
        width: parent.width
        topPadding: 10
        bottomPadding: 10
        text: "Peer list unavailable\n" + root.statusError
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontSecondary
        color: Theme.redText
    }

    // Peers
    Repeater {
        model: SysInfo.tsRunning ? root.peers.slice(0, 8) : []

        delegate: Rectangle {
            id: peerRow

            required property var modelData

            width: parent.width - 4
            x: 2
            height: Theme.rowHeight
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
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontBody
                    font.weight: peerRow.modelData.online ? Theme.weightMedium : Theme.weightRegular
                    color: peerRow.modelData.online ? Theme.textHi : Theme.textMid
                }

                Text {
                    visible: peerRow.modelData.os !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: peerRow.modelData.os
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textDim
                }

                Rectangle {
                    visible: peerRow.modelData.exit || peerRow.modelData.exitOption
                    anchors.verticalCenter: parent.verticalCenter
                    width: exitText.implicitWidth + 10
                    height: exitText.implicitHeight + 4
                    radius: 4
                    color: peerRow.modelData.exit ? Theme.accentBgSoft : Theme.hoverFill

                    Text {
                        id: exitText
                        anchors.centerIn: parent
                        text: peerRow.modelData.exit ? "EXIT" : "exit node"
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontCaption
                        font.weight: Theme.weightSemibold
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
                font.pixelSize: Theme.fontCaption
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
        height: Theme.rowHeight

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: {
                if (!SysInfo.tsRunning || !root.statusKnown)
                    return "click a device to copy its IP";
                // Never count to zero on a failed status run: that is the
                // one thing an empty tailnet is allowed to say.
                if (root.statusError !== "")
                    return "peer status unavailable";
                const online = root.peers.filter(p => p.online).length;
                return online + " of " + root.peers.length + " devices online · click to copy IP";
            }
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontSecondary
            color: Theme.textDim
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Admin console"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontSecondary
            font.weight: Theme.weightMedium
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
