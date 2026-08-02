import QtQuick
import Quickshell
import "../Common"

// T3 Code detail view: the active agent sessions on the remote server,
// ranked needs-attention → running → recently finished → idle. Settled
// and snoozed threads are left to the web client — this is the inbox.
// Clicking a session expands it in place: pending approvals can be
// answered directly, a quick prompt starts a new turn, and running
// turns can be interrupted — the web client is one click away for
// anything richer.
Surface {
    id: root

    readonly property int maxRows: 9
    property string expandedId: ""

    Component.onDestruction: T3Code.closeDetail()

    Connections {
        target: T3Code

        // The expanded row can leave the list under you — settled from
        // another client, snoozed, or aged out. Drop its subscription too.
        function onThreadsChanged() {
            if (root.expandedId !== ""
                    && !T3Code.threads.some(t => t.id === root.expandedId)) {
                root.expandedId = "";
                T3Code.closeDetail();
            }
        }
    }

    function toggleRow(threadId) {
        if (expandedId === threadId) {
            expandedId = "";
            T3Code.closeDetail();
        } else {
            expandedId = threadId;
            T3Code.openDetail(threadId);
        }
    }

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

    // Small pill button used across the expanded rows.
    component ActionButton: Rectangle {
        id: btn

        property string label: ""
        property color tint: Theme.textMid
        property color fill: Theme.hoverFill
        signal activated()

        width: btnText.implicitWidth + 18
        height: 22
        radius: Theme.chipRadius
        color: btnMouse.containsMouse ? Qt.lighter(fill, 1.5) : fill

        Text {
            id: btnText
            anchors.centerIn: parent
            text: btn.label
            font.family: Theme.fontSans
            font.pixelSize: 11
            font.weight: 500
            color: btn.tint
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: btn.activated()
        }
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
        text: {
            if (T3Code.settledCount > 0)
                return "All caught up · " + T3Code.settledCount + " settled";
            if (T3Code.snoozedCount > 0)
                return "All caught up · " + T3Code.snoozedCount + " snoozed";
            return "No sessions";
        }
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

            readonly property bool expanded: root.expandedId === modelData.id
            readonly property bool busy: modelData.cls === "running"
            readonly property bool quiet: modelData.cls === "idle"

            width: parent.width - 4
            x: 2
            height: rowColumn.implicitHeight
            radius: Theme.rowRadius
            color: expanded ? Theme.cardFill
                 : rowMouse.containsMouse ? Theme.hoverFill
                 : modelData.cls === "attention" ? Theme.amberBg
                 : "transparent"
            opacity: quiet && !expanded && !rowMouse.containsMouse ? 0.6 : 1

            Column {
                id: rowColumn
                width: parent.width

                // Main line
                Item {
                    width: parent.width
                    height: 40

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
                        onClicked: root.toggleRow(row.modelData.id)
                    }
                }

                // Expanded detail
                Column {
                    visible: row.expanded
                    width: parent.width
                    spacing: 6
                    bottomPadding: 10

                    Text {
                        visible: row.modelData.pendingApprovals && T3Code.detailLoading
                        x: 27
                        text: "Loading approvals…"
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        color: Theme.textDim
                    }

                    // Approval cards
                    Repeater {
                        model: row.expanded ? T3Code.detailApprovals : []

                        delegate: Rectangle {
                            id: approval

                            required property var modelData

                            x: 10
                            width: rowColumn.width - 20
                            height: approvalCol.implicitHeight + 16
                            radius: Theme.rowRadius
                            color: Theme.amberBg
                            border.width: 1
                            border.color: Theme.amberBorder

                            Column {
                                id: approvalCol
                                x: 10
                                y: 8
                                width: parent.width - 20
                                spacing: 6

                                Text {
                                    text: approval.modelData.kind === "file-change" ? "File change"
                                        : approval.modelData.kind === "file-read" ? "File read"
                                        : "Run command"
                                    font.family: Theme.fontSans
                                    font.pixelSize: 10
                                    font.weight: 600
                                    font.letterSpacing: 0.5
                                    color: Theme.amber
                                }

                                Text {
                                    visible: approval.modelData.detail !== ""
                                    width: parent.width
                                    text: approval.modelData.detail
                                    wrapMode: Text.WrapAnywhere
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                    color: Theme.textMid
                                }

                                Row {
                                    spacing: 6

                                    ActionButton {
                                        label: "Allow"
                                        tint: Theme.accentFg
                                        fill: Theme.accent
                                        onActivated: T3Code.respondApproval(row.modelData.id, approval.modelData.requestId, "accept")
                                    }

                                    ActionButton {
                                        label: "Allow session"
                                        tint: Theme.accent
                                        fill: Theme.accentBgSoft
                                        onActivated: T3Code.respondApproval(row.modelData.id, approval.modelData.requestId, "acceptForSession")
                                    }

                                    ActionButton {
                                        label: "Deny"
                                        tint: Theme.redText
                                        fill: Theme.redBgSoft
                                        onActivated: T3Code.respondApproval(row.modelData.id, approval.modelData.requestId, "decline")
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: row.modelData.pendingInput && !T3Code.detailLoading
                            && T3Code.detailApprovals.length === 0
                        x: 27
                        width: rowColumn.width - 40
                        text: "The agent asked a question — answer it in the web client."
                        wrapMode: Text.WordWrap
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        color: Theme.textLow
                    }

                    // Quick prompt
                    Rectangle {
                        x: 10
                        width: rowColumn.width - 20
                        height: 28
                        radius: Theme.chipRadius
                        color: Theme.hoverFill
                        border.width: 1
                        border.color: promptInput.activeFocus ? Theme.accentBgSoft : Theme.hairlineSoft

                        TextInput {
                            id: promptInput
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 34
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            color: Theme.textHi
                            clip: true
                            onAccepted: sendPrompt.activated()

                            Text {
                                visible: promptInput.text === "" && !promptInput.activeFocus
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.busy ? "Queue a follow-up…" : "Send a prompt…"
                                font.family: Theme.fontSans
                                font.pixelSize: 11
                                color: Theme.textFaint
                            }
                        }

                        MouseArea {
                            id: sendPrompt
                            anchors.right: parent.right
                            width: 30
                            height: parent.height
                            hoverEnabled: true
                            enabled: promptInput.text.trim() !== ""

                            function activated() {
                                const text = promptInput.text.trim();
                                if (text === "")
                                    return;
                                T3Code.startTurn(row.modelData.id, text);
                                promptInput.text = "";
                            }

                            onClicked: activated()

                            Text {
                                anchors.centerIn: parent
                                text: "↑"
                                font.family: Theme.fontMono
                                font.pixelSize: 12
                                font.weight: 700
                                color: promptInput.text.trim() !== "" ? Theme.accent : Theme.textFaint
                            }
                        }
                    }

                    // Actions
                    Row {
                        x: 10
                        spacing: 6

                        ActionButton {
                            visible: row.busy
                            label: "Interrupt"
                            tint: Theme.redText
                            fill: Theme.redBgSoft
                            onActivated: T3Code.interrupt(row.modelData.id)
                        }

                        ActionButton {
                            visible: row.modelData.cls === "done" || row.modelData.cls === "error"
                            label: "Mark reviewed"
                            onActivated: {
                                T3Code.settle(row.modelData.id);
                                root.expandedId = "";
                                T3Code.closeDetail();
                            }
                        }

                        ActionButton {
                            label: "Open in browser"
                            tint: Theme.accent
                            fill: Theme.accentBgSoft
                            onActivated: root.openThread(row.modelData.id)
                        }
                    }
                }
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
