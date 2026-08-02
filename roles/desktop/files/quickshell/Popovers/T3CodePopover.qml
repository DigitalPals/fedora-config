import QtQuick
import Quickshell
import "../Common"

// T3 Code overview (design 2e): a triage inbox. Sessions blocked on the
// user are pinned first as amber cards with their pending approvals
// answerable inline and a quick follow-up box; running turns group below
// with a one-click stop; finished and idle work collapses to a single
// summary row. Settled and snoozed threads stay in the web client —
// this is the inbox, and the web client is one click away for anything
// richer.
Surface {
    id: root

    readonly property int maxNeedsYou: 4
    readonly property int maxRunning: 6

    readonly property var needsYou: T3Code.threads.filter(t => t.cls === "attention" || t.cls === "error")
    readonly property var runningThreads: T3Code.threads.filter(t => t.cls === "running")
    readonly property var quietThreads: T3Code.threads.filter(t => t.cls === "done" || t.cls === "idle")
    readonly property int quietDone: quietThreads.filter(t => t.cls === "done").length
    readonly property int quietIdle: quietThreads.length - quietDone
    readonly property int hiddenCount: Math.max(0, needsYou.length - maxNeedsYou)
        + Math.max(0, runningThreads.length - maxRunning)

    // Which needs-you card holds the approval subscription: the most
    // urgent by default; clicking another card moves it there.
    property string chosenId: ""
    property bool quietExpanded: false

    spacing: 6

    // The one detail subscription follows the pinned cards, so approvals
    // are already loaded when the popover appears — no expand step.
    function ensureDetail() {
        if (T3Code.state !== "connected") {
            if (T3Code.detailThreadId !== "")
                T3Code.closeDetail();
            return;
        }
        let id = chosenId;
        if (id === "" || !needsYou.some(t => t.id === id))
            id = needsYou.length > 0 ? needsYou[0].id : "";
        chosenId = id;
        if (id === "") {
            if (T3Code.detailThreadId !== "")
                T3Code.closeDetail();
        } else if (T3Code.detailThreadId !== id) {
            T3Code.openDetail(id);
        }
    }

    onNeedsYouChanged: ensureDetail()
    Component.onCompleted: ensureDetail()
    Component.onDestruction: T3Code.closeDetail()

    function openThread(threadId) {
        Quickshell.execDetached(["xdg-open", T3Code.threadUrl(threadId)]);
        Popouts.close();
    }

    function settleDone() {
        for (const t of quietThreads) {
            if (t.cls === "done")
                T3Code.settle(t.id);
        }
    }

    // Approval answer / stop pill.
    component Pill: Rectangle {
        id: pill

        property string label: ""
        property color tint: Theme.textMid
        property color fill: Theme.hoverFill
        property int weight: 500
        signal activated()

        width: pillText.implicitWidth + 20
        height: 22
        radius: Theme.chipRadius
        color: pillMouse.containsMouse ? Qt.lighter(fill, 1.3) : fill

        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            font.family: Theme.fontSans
            font.pixelSize: 11
            font.weight: pill.weight
            color: pill.tint
        }

        MouseArea {
            id: pillMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: pill.activated()
        }
    }

    component OpenLink: Text {
        id: link

        property string threadId: ""

        text: "open ↗"
        font.family: Theme.fontSans
        font.pixelSize: 10
        color: openLinkMouse.containsMouse ? "#c8e2f4" : Theme.accent

        MouseArea {
            id: openLinkMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.openThread(link.threadId)
        }
    }

    component GroupLabel: Text {
        leftPadding: 6
        topPadding: 2
        font.family: Theme.fontSans
        font.pixelSize: 10
        font.weight: 600
        font.letterSpacing: 0.6
        color: Theme.textDim
    }

    // Header: brand mark + wordmark, environment and counts below, and a
    // reconnect button on the right.
    Item {
        width: parent.width
        height: 40

        Column {
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Row {
                spacing: 6

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 11
                    width: 18
                    sourceSize: Qt.size(36, 22)
                    fillMode: Image.PreserveAspectFit
                    source: Quickshell.shellDir + "/assets/"
                        + (T3Code.state === "connected" ? "t3.svg" : "t3-dim.svg")
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Code"
                    font.family: Theme.fontSans
                    font.pixelSize: 14
                    font.weight: 700
                    font.letterSpacing: -0.3
                    color: "#fafafa"
                }
            }

            Text {
                text: {
                    switch (T3Code.state) {
                    case "connected": {
                        const env = T3Code.environmentLabel !== "" ? T3Code.environmentLabel : "connected";
                        return env + " · " + T3Code.runningCount + " running · "
                            + T3Code.attentionCount + " waiting";
                    }
                    case "connecting":
                        return "connecting…";
                    case "unpaired":
                        return "not paired";
                    default:
                        return "server unreachable — retrying";
                    }
                }
                font.family: Theme.fontSans
                font.pixelSize: 10
                color: Theme.textDim
            }
        }

        Rectangle {
            visible: T3Code.paired
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            height: 22
            radius: 6
            color: refreshMouse.containsMouse ? Theme.hoverFill : "transparent"

            Text {
                anchors.centerIn: parent
                text: "↻"
                font.family: Theme.fontSans
                font.pixelSize: 12
                color: refreshMouse.containsMouse ? Theme.textMid : Theme.textLow
            }

            MouseArea {
                id: refreshMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: T3Code.connect()
            }
        }
    }

    // Unpaired guidance
    Column {
        visible: T3Code.state === "unpaired"
        width: parent.width
        topPadding: 4
        bottomPadding: 8
        spacing: 6

        Text {
            width: parent.width - 12
            x: 6
            text: "Not paired. Create a pairing URL in the T3 Code web client (Settings → Connections), then run:"
            wrapMode: Text.WordWrap
            font.family: Theme.fontSans
            font.pixelSize: 11
            color: Theme.textDim
        }

        Text {
            width: parent.width - 12
            x: 6
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
        topPadding: 8
        bottomPadding: 10
        text: T3Code.state === "connecting" ? "Connecting…" : "Server unreachable — retrying"
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontSans
        font.pixelSize: 11
        color: Theme.textDim
    }

    Text {
        visible: T3Code.state === "connected" && T3Code.threads.length === 0
        width: parent.width
        topPadding: 8
        bottomPadding: 10
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

    // ---- NEEDS YOU: pinned cards, approvals inline ---------------------

    GroupLabel {
        visible: root.needsYou.length > 0
        text: "NEEDS YOU"
        color: Theme.amber
    }

    Column {
        visible: T3Code.state === "connected" && root.needsYou.length > 0
        width: parent.width
        spacing: 6

        Repeater {
            model: T3Code.state === "connected" ? root.needsYou.slice(0, root.maxNeedsYou) : []

            delegate: Rectangle {
                id: card

                required property var modelData

                readonly property bool isError: modelData.cls === "error"
                readonly property bool detail: T3Code.detailThreadId === modelData.id

                width: parent.width - 4
                x: 2
                height: cardCol.implicitHeight + 20
                radius: 10
                color: isError ? Theme.redBgSoft : Theme.amberBgSoft
                border.width: 1
                border.color: isError ? Theme.redBorder : Theme.amberBorder

                // A card without the subscription takes it on click.
                MouseArea {
                    anchors.fill: parent
                    enabled: !card.detail
                    onClicked: {
                        root.chosenId = card.modelData.id;
                        root.ensureDetail();
                    }
                }

                Column {
                    id: cardCol
                    x: 12
                    y: 10
                    width: parent.width - 24
                    spacing: 8

                    Item {
                        width: parent.width
                        height: 15

                        Text {
                            anchors.left: parent.left
                            anchors.right: cardProject.left
                            anchors.rightMargin: 8
                            anchors.baseline: cardProject.baseline
                            text: card.modelData.title
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: 500
                            color: Theme.textHi
                            elide: Text.ElideRight
                        }

                        Text {
                            id: cardProject
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            text: card.modelData.project
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            color: Theme.textDim
                        }
                    }

                    Text {
                        visible: card.detail && T3Code.detailLoading && card.modelData.pendingApprovals
                        text: "Loading approvals…"
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        color: Theme.textDim
                    }

                    // One block per pending approval: the request itself,
                    // then the answers.
                    Repeater {
                        model: card.detail ? T3Code.detailApprovals : []

                        delegate: Column {
                            id: approval

                            required property var modelData
                            required property int index

                            width: parent.width
                            spacing: 8

                            Rectangle {
                                width: parent.width
                                height: reqRow.implicitHeight + 12
                                radius: 6
                                color: Qt.rgba(0, 0, 0, 0.25)

                                Row {
                                    id: reqRow
                                    x: 8
                                    y: 6
                                    width: parent.width - 16
                                    spacing: 6

                                    Text {
                                        id: reqKind
                                        text: approval.modelData.kind === "file-change" ? "edit"
                                            : approval.modelData.kind === "file-read" ? "read"
                                            : "run"
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                        color: Theme.amber
                                    }

                                    Text {
                                        width: parent.width - reqKind.width - 6
                                        text: approval.modelData.detail !== ""
                                            ? approval.modelData.detail : "(no detail)"
                                        wrapMode: Text.WrapAnywhere
                                        maximumLineCount: 4
                                        elide: Text.ElideRight
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                        color: Theme.textMid
                                    }
                                }
                            }

                            Item {
                                width: parent.width
                                height: 22

                                Row {
                                    spacing: 6

                                    Pill {
                                        label: "Allow"
                                        tint: Theme.accentFg
                                        fill: Theme.accent
                                        weight: 600
                                        onActivated: T3Code.respondApproval(card.modelData.id,
                                            approval.modelData.requestId, "accept")
                                    }

                                    Pill {
                                        label: "Session"
                                        tint: Theme.accent
                                        fill: Theme.accentBg
                                        onActivated: T3Code.respondApproval(card.modelData.id,
                                            approval.modelData.requestId, "acceptForSession")
                                    }

                                    Pill {
                                        label: "Deny"
                                        tint: Theme.redText
                                        fill: Theme.redBg
                                        onActivated: T3Code.respondApproval(card.modelData.id,
                                            approval.modelData.requestId, "decline")
                                    }
                                }

                                OpenLink {
                                    visible: approval.index === 0
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    threadId: card.modelData.id
                                }
                            }
                        }
                    }

                    // No approvals to answer: say why the card is here.
                    Item {
                        visible: card.detail
                            ? !T3Code.detailLoading && T3Code.detailApprovals.length === 0
                            : true
                        width: parent.width
                        height: 14

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                if (card.isError)
                                    return "failed — details in the web client";
                                if (card.detail)
                                    return "asked a question — answer below or open it";
                                return card.modelData.pendingApprovals
                                    ? "waiting for approval — click to review"
                                    : "has a question";
                            }
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            color: Theme.textLow
                        }

                        OpenLink {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            threadId: card.modelData.id
                        }
                    }

                    // Quick follow-up straight into the session.
                    Rectangle {
                        width: parent.width
                        height: 26
                        radius: Theme.chipRadius
                        color: Theme.hoverFill
                        border.width: 1
                        border.color: followInput.activeFocus ? Theme.accentBgSoft : Theme.hairlineSoft

                        TextInput {
                            id: followInput
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 30
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            color: Theme.textHi
                            clip: true
                            onAccepted: followSend.activated()

                            Text {
                                visible: followInput.text === "" && !followInput.activeFocus
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Send a follow-up…"
                                font.family: Theme.fontSans
                                font.pixelSize: 11
                                color: Theme.textFaint
                            }
                        }

                        MouseArea {
                            id: followSend
                            anchors.right: parent.right
                            width: 28
                            height: parent.height
                            hoverEnabled: true

                            function activated() {
                                const text = followInput.text.trim();
                                if (text === "")
                                    return;
                                T3Code.startTurn(card.modelData.id, text);
                                followInput.text = "";
                            }

                            onClicked: activated()

                            Text {
                                anchors.centerIn: parent
                                text: "↑"
                                font.family: Theme.fontMono
                                font.pixelSize: 12
                                font.weight: 700
                                color: followInput.text.trim() !== "" ? Theme.accent : Theme.textFaint
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- RUNNING: grouped rows with one-click stop ---------------------

    GroupLabel {
        visible: root.runningThreads.length > 0
        text: "RUNNING"
    }

    Column {
        visible: T3Code.state === "connected" && root.runningThreads.length > 0
        width: parent.width

        Repeater {
            model: T3Code.state === "connected" ? root.runningThreads.slice(0, root.maxRunning) : []

            delegate: Rectangle {
                id: runRow

                required property var modelData

                width: parent.width - 4
                x: 2
                height: 40
                radius: 8
                color: runMouse.containsMouse ? Theme.hoverFill : "transparent"

                MouseArea {
                    id: runMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.openThread(runRow.modelData.id)
                }

                Rectangle {
                    id: runDot
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7
                    height: 7
                    radius: 4
                    color: Theme.accent

                    SequentialAnimation on opacity {
                        running: true
                        loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0.25; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.25; to: 1; duration: 900; easing.type: Easing.InOutSine }
                    }
                }

                Column {
                    anchors.left: runDot.right
                    anchors.leftMargin: 10
                    anchors.right: stopPill.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        width: parent.width
                        text: runRow.modelData.title
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                        font.weight: 500
                        color: Theme.textHi
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: runRow.modelData.project
                            + (runRow.modelData.model !== "" ? " · " + runRow.modelData.model : "")
                            + " · " + T3Code.relTime(runRow.modelData.updatedAt)
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        color: Theme.textDim
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    id: stopPill
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: stopText.implicitWidth + 16
                    height: 20
                    radius: 6
                    color: stopMouse.containsMouse ? Qt.lighter(Theme.redBg, 1.3) : Theme.redBg

                    Text {
                        id: stopText
                        anchors.centerIn: parent
                        text: "Stop"
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        font.weight: 500
                        color: Theme.redText
                    }

                    MouseArea {
                        id: stopMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: T3Code.interrupt(runRow.modelData.id)
                    }
                }
            }
        }
    }

    // ---- Done / idle: one summary row, expandable ----------------------

    Rectangle {
        visible: T3Code.state === "connected" && root.quietThreads.length > 0
        width: parent.width - 4
        x: 2
        height: 30
        radius: 8
        color: quietMouse.containsMouse ? Theme.hoverFill : Qt.rgba(1, 1, 1, 0.03)

        MouseArea {
            id: quietMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.quietExpanded = !root.quietExpanded
        }

        Rectangle {
            id: quietDot
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 7
            height: 7
            radius: 4
            color: Theme.textMid
        }

        Text {
            anchors.left: quietDot.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: {
                const parts = [];
                if (root.quietDone > 0)
                    parts.push("Done · " + root.quietDone);
                if (root.quietIdle > 0)
                    parts.push("Idle · " + root.quietIdle);
                return parts.join("  ·  ");
            }
            font.family: Theme.fontSans
            font.pixelSize: 11
            color: Theme.textLow
        }

        Text {
            visible: root.quietDone > 0
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "mark reviewed"
            font.family: Theme.fontSans
            font.pixelSize: 10
            color: reviewMouse.containsMouse ? "#c8e2f4" : Theme.accent

            MouseArea {
                id: reviewMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.settleDone()
            }
        }
    }

    Column {
        visible: T3Code.state === "connected" && root.quietExpanded && root.quietThreads.length > 0
        width: parent.width

        Repeater {
            model: T3Code.state === "connected" && root.quietExpanded ? root.quietThreads : []

            delegate: Rectangle {
                id: quietRow

                required property var modelData

                readonly property bool idle: modelData.cls === "idle"

                width: parent.width - 4
                x: 2
                height: 36
                radius: 8
                color: quietRowMouse.containsMouse ? Theme.hoverFill : "transparent"
                opacity: idle && !quietRowMouse.containsMouse ? 0.6 : 1

                MouseArea {
                    id: quietRowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.openThread(quietRow.modelData.id)
                }

                Rectangle {
                    id: quietRowDot
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7
                    height: 7
                    radius: 4
                    color: quietRow.idle ? Theme.dotDim : Theme.textMid
                }

                Column {
                    anchors.left: quietRowDot.right
                    anchors.leftMargin: 10
                    anchors.right: quietTime.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        width: parent.width
                        text: quietRow.modelData.title
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                        color: Theme.textMid
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: quietRow.modelData.project
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        color: Theme.textDim
                        elide: Text.ElideRight
                    }
                }

                Text {
                    id: quietTime
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: T3Code.relTime(quietRow.modelData.updatedAt)
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                    color: Theme.textDim
                }
            }
        }
    }

    HDivider {
        visible: T3Code.state === "connected" && T3Code.threads.length > 0
    }

    // Footer: connection line left, web client right.
    Item {
        width: parent.width
        height: 24

        Row {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
                text: {
                    let s = T3Code.state === "connected" ? "connected" : T3Code.state;
                    if (root.hiddenCount > 0)
                        s += " · +" + root.hiddenCount + " more";
                    return s + (T3Code.host !== "" ? " · " : "");
                }
                font.family: Theme.fontSans
                font.pixelSize: 10
                color: Theme.textDim
            }

            Text {
                visible: T3Code.host !== ""
                text: T3Code.host.replace(/^https?:\/\//, "")
                font.family: Theme.fontMono
                font.pixelSize: 10
                color: Theme.textLow
            }
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 6
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
