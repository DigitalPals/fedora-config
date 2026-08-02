import QtQuick
import Quickshell
import "../Common"

// T3 Code detail view: live agent sessions on the remote server,
// ranked needs-attention → running → recently finished → idle.
// Clicking a session opens its thread in the web client.
Surface {
    id: root

    readonly property int maxRows: 9

    function statusColor(cls) {
        switch (cls) {
        case "attention":
            return Theme.amber;
        case "error":
            return Theme.red;
        case "running":
            return Theme.accent;
        case "done":
            return Theme.textMid;
        default:
            return Theme.dotDim;
        }
    }

    function statusWord(cls) {
        switch (cls) {
        case "attention":
            return "needs you";
        case "error":
            return "error";
        case "running":
            return "running";
        case "done":
            return "done";
        default:
            return "";
        }
    }

    function openThread(threadId) {
        Quickshell.execDetached(["xdg-open", T3Code.threadUrl(threadId)]);
        Popouts.close();
    }

    // Header
    Item {
        width: parent.width
        height: 36

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "T3 Code"
            font.family: Theme.fontSans
            font.pixelSize: 12
            font.weight: 600
            color: Theme.textHi
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 7
                height: 7
                radius: 4
                color: T3Code.state === "connected" ? Theme.accent
                     : T3Code.state === "connecting" ? Theme.amber
                     : Theme.dotDim
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (T3Code.state === "connected")
                        return T3Code.environmentLabel !== "" ? T3Code.environmentLabel : "connected";
                    return T3Code.state;
                }
                font.family: Theme.fontSans
                font.pixelSize: 11
                color: Theme.textLow
            }
        }
    }

    // Unpaired / offline guidance
    Column {
        visible: T3Code.state === "unpaired"
        width: parent.width
        topPadding: 10
        bottomPadding: 14
        spacing: 6

        Text {
            width: parent.width - 20
            x: 10
            text: "Not paired. Create a pairing URL in the T3 Code web client (Settings → Connections), then run:"
            wrapMode: Text.WordWrap
            font.family: Theme.fontSans
            font.pixelSize: 11
            color: Theme.textDim
        }

        Text {
            width: parent.width - 20
            x: 10
            text: T3Code.pairHint
            wrapMode: Text.WrapAnywhere
            font.family: Theme.fontMono
            font.pixelSize: 10
            color: Theme.textLow
        }
    }

    Text {
        visible: T3Code.state === "offline" || T3Code.state === "connecting"
        width: parent.width
        topPadding: 14
        bottomPadding: 14
        text: T3Code.state === "connecting" ? "Connecting…" : "Server unreachable — retrying"
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontSans
        font.pixelSize: 11
        color: Theme.textDim
    }

    Text {
        visible: T3Code.state === "connected" && T3Code.threads.length === 0
        width: parent.width
        topPadding: 14
        bottomPadding: 14
        text: "No sessions"
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontSans
        font.pixelSize: 11
        color: Theme.textDim
    }

    // Sessions
    Repeater {
        model: T3Code.state === "connected" ? T3Code.threads.slice(0, root.maxRows) : []

        delegate: Rectangle {
            id: row

            required property var modelData

            readonly property bool busy: modelData.cls === "running"
            readonly property bool quiet: modelData.cls === "idle"

            width: parent.width - 4
            x: 2
            height: 40
            radius: Theme.rowRadius
            color: rowMouse.containsMouse ? Theme.hoverFill
                 : modelData.cls === "attention" ? Theme.amberBg
                 : "transparent"
            opacity: quiet && !rowMouse.containsMouse ? 0.6 : 1

            Rectangle {
                id: dot
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 7
                height: 7
                radius: 4
                color: root.statusColor(row.modelData.cls)

                SequentialAnimation on opacity {
                    running: row.busy
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.25; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.25; to: 1; duration: 900; easing.type: Easing.InOutSine }
                }
            }

            Column {
                anchors.left: dot.right
                anchors.leftMargin: 10
                anchors.right: meta.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    width: parent.width
                    text: row.modelData.title
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight: row.quiet ? 400 : 500
                    color: row.quiet ? Theme.textMid : Theme.textHi
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: row.modelData.project
                        + (row.modelData.model !== "" ? " · " + row.modelData.model : "")
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    color: Theme.textDim
                    elide: Text.ElideRight
                }
            }

            Column {
                id: meta
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    anchors.right: parent.right
                    text: root.statusWord(row.modelData.cls)
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    font.weight: row.modelData.cls === "attention" ? 600 : 400
                    color: root.statusColor(row.modelData.cls)
                }

                Text {
                    anchors.right: parent.right
                    text: T3Code.relTime(row.modelData.updatedAt)
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                    color: Theme.textDim
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.openThread(row.modelData.id)
            }
        }
    }

    HDivider {
        visible: T3Code.state === "connected" && T3Code.threads.length > 0
    }

    // Footer
    Item {
        width: parent.width
        height: 26

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: {
                if (T3Code.state !== "connected")
                    return "";
                const total = T3Code.threads.length;
                const hidden = Math.max(0, total - root.maxRows);
                let s = T3Code.runningCount + " running · " + T3Code.attentionCount + " waiting";
                if (hidden > 0)
                    s += " · " + hidden + " more";
                return s;
            }
            font.family: Theme.fontSans
            font.pixelSize: 11
            color: Theme.textDim
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Open T3 Code"
            font.family: Theme.fontSans
            font.pixelSize: 11
            font.weight: 500
            color: openMouse.containsMouse ? "#c8e2f4" : Theme.accent

            MouseArea {
                id: openMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    Quickshell.execDetached(["xdg-open", T3Code.host !== "" ? T3Code.host : "https://app.t3.codes"]);
                    Popouts.close();
                }
            }
        }
    }
}
