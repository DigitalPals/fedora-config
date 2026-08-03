import QtQuick
import Quickshell
import "../Common"

Column {
    id: root

    required property string threadId
    property int maxHeight: 720
    property int visibleMessages: 10
    property bool confirmStop: false
    property bool snoozeOpen: false
    property bool menuOpen: false
    property bool followTail: true
    signal backRequested()
    signal newPlanRequested(var plan)

    readonly property var thread: T3Code.projectedThread(threadId)
    readonly property var history: T3Code.historyPage(T3Code.detailMessages, visibleMessages)
    readonly property bool working: thread !== null && thread.cls === "running"
    readonly property string workingTime: working
        ? T3Code.workingTimerLabel(thread.workingStartedAt) : ""
    readonly property bool hasRequests: thread !== null && (thread.pendingApprovals || thread.pendingInput
        || T3Code.detailApprovals.length > 0 || T3Code.detailPendingInputs.length > 0)
    readonly property bool composerIdle: thread !== null && thread.lifecycle === "active"
        && thread.canLifecycle && !hasRequests && !T3Code.detailLoading
    readonly property bool canCompose: composerIdle
        && (!thread.planReady || T3Code.threadDraft(threadId).interactionMode === "plan")
    readonly property var plan: T3Code.detailActionablePlan
    readonly property bool planTooLong: plan
        && T3Code.maxPromptChars < ("PLEASE IMPLEMENT THIS PLAN:\n" + plan.planMarkdown.trim()).length

    spacing: 5

    function scrollToEnd() {
        if (!followTail)
            return;
        Qt.callLater(() => {
            if (root.followTail)
                flick.contentY = Math.max(0, flick.contentHeight - flick.height);
        });
    }

    function showEarlier() {
        followTail = false;
        const previousHeight = flick.contentHeight;
        visibleMessages += 10;
        Qt.callLater(() => {
            flick.contentY = Math.max(0, flick.contentY + flick.contentHeight - previousHeight);
        });
    }

    component Action: Rectangle {
        id: action
        property string label: ""
        property color tint: Theme.textLow
        property color fill: Theme.hoverFill
        signal triggered()

        width: labelText.implicitWidth + 14
        height: 22
        radius: 6
        color: actionMouse.containsMouse && enabled ? Qt.lighter(fill, 1.2) : fill
        opacity: enabled ? 1 : 0.4
        activeFocusOnTab: enabled && visible
        border.width: activeFocus ? 1 : 0
        border.color: Theme.accent

        Keys.onPressed: event => {
            if (!action.enabled)
                return;
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                action.triggered();
                event.accepted = true;
            }
        }

        Text {
            id: labelText
            anchors.centerIn: parent
            text: action.label
            font.family: Theme.fontSans
            font.pixelSize: 10
            font.weight: 600
            color: action.tint
        }

        MouseArea {
            id: actionMouse
            anchors.fill: parent
            enabled: action.enabled
            hoverEnabled: true
            onClicked: action.triggered()
        }
    }

    component InfoCard: Rectangle {
        id: card
        property string heading: ""
        property string body: ""
        property color headingColor: Theme.textDim
        property color fill: Theme.cardFill
        property color outline: Theme.hairlineSoft

        width: parent ? parent.width : 0
        height: cardColumn.implicitHeight + 14
        radius: 8
        color: fill
        border.width: 1
        border.color: outline

        Column {
            id: cardColumn
            x: 7
            y: 7
            width: parent.width - 14
            spacing: 3

            Text {
                width: parent.width
                text: card.heading
                font.family: Theme.fontSans
                font.pixelSize: 10
                font.weight: 650
                font.letterSpacing: 0.7
                color: card.headingColor
            }

            Text {
                width: parent.width
                text: card.body
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                lineHeight: 1.4
                maximumLineCount: 5
                elide: Text.ElideRight
                font.family: Theme.fontSans
                font.pixelSize: 11
                color: Theme.textMid
            }
        }
    }

    // Your messages get a tinted card; T3's replies are plain prose on a
    // 2px rail (design 5c). Prose wraps at word boundaries — mid-word breaks
    // only happen when a single token exceeds the line.
    component MessageCard: Item {
        id: messageCard
        required property var message
        property bool expanded: false
        readonly property bool fromUser: message.role === "user"
        readonly property bool longMessage: typeof message.text === "string"
            && (message.text.length > 700 || message.text.split("\n").length > 8)

        width: parent ? parent.width : 0
        height: messageColumn.implicitHeight + (fromUser ? 20 : 6)

        Rectangle {
            visible: messageCard.fromUser
            anchors.fill: parent
            radius: 10
            color: Theme.accentBgSoft
            border.width: 1
            border.color: Qt.rgba(158 / 255, 203 / 255, 235 / 255, 0.18)
        }

        Rectangle {
            visible: !messageCard.fromUser
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 2
            radius: 1
            color: Qt.rgba(1, 1, 1, 0.10)
        }

        Column {
            id: messageColumn
            x: messageCard.fromUser ? 11 : 13
            y: messageCard.fromUser ? 10 : 3
            width: parent.width - (messageCard.fromUser ? 22 : 15)
            spacing: 4

            Item {
                width: parent.width
                height: 15

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: messageCard.fromUser ? "You"
                        : messageCard.message.role === "assistant" ? "T3 Code" : "System"
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    font.weight: 600
                    color: messageCard.fromUser ? Theme.accent : Theme.textLow
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: messageCard.message.streaming === true ? "streaming…"
                        : T3Code.relTime(messageCard.message.updatedAt
                            ?? messageCard.message.createdAt)
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                    color: Theme.textDim
                }
            }

            Text {
                width: parent.width
                text: messageCard.message.text ?? ""
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                lineHeight: 1.4
                maximumLineCount: messageCard.expanded ? 100000 : 8
                elide: messageCard.expanded ? Text.ElideNone : Text.ElideRight
                font.family: Theme.fontSans
                font.pixelSize: 12
                color: Theme.textMid
            }

            Action {
                visible: messageCard.longMessage
                label: messageCard.expanded ? "Show less" : "Expand"
                onTriggered: messageCard.expanded = !messageCard.expanded
            }
        }
    }

    component IconButton: Rectangle {
        id: iconButton
        property string glyph: ""
        property color tint: Theme.textMid
        signal triggered()

        width: 26
        height: 26
        radius: 7
        color: iconMouse.containsMouse && enabled ? Theme.hoverFillStrong : Theme.hoverFill
        opacity: enabled ? 1 : 0.4
        activeFocusOnTab: enabled && visible
        border.width: activeFocus ? 1 : 0
        border.color: Theme.accent

        Keys.onPressed: event => {
            if (!iconButton.enabled)
                return;
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                iconButton.triggered();
                event.accepted = true;
            }
        }

        Text {
            anchors.centerIn: parent
            text: iconButton.glyph
            font.family: Theme.fontSans
            font.pixelSize: 13
            font.weight: 600
            color: iconButton.tint
        }

        MouseArea {
            id: iconMouse
            anchors.fill: parent
            enabled: iconButton.enabled
            hoverEnabled: true
            onClicked: iconButton.triggered()
        }
    }

    component MenuEntry: Rectangle {
        id: menuEntry
        property string label: ""
        property color tint: Theme.textMid
        signal triggered()

        width: parent ? parent.width : 0
        height: 28
        radius: 6
        color: entryMouse.containsMouse && enabled ? Theme.hoverFillStrong : "transparent"
        opacity: enabled ? 1 : 0.4
        activeFocusOnTab: enabled && visible
        border.width: activeFocus ? 1 : 0
        border.color: Theme.accent

        Keys.onPressed: event => {
            if (!menuEntry.enabled)
                return;
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                menuEntry.triggered();
                event.accepted = true;
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 9
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            text: menuEntry.label
            elide: Text.ElideRight
            font.family: Theme.fontSans
            font.pixelSize: 11
            font.weight: 500
            color: menuEntry.tint
        }

        MouseArea {
            id: entryMouse
            anchors.fill: parent
            enabled: menuEntry.enabled
            hoverEnabled: true
            onClicked: menuEntry.triggered()
        }
    }

    // Left-aligned header; Stop / Snooze / Settle live behind ⋯ so the
    // always-on row is just navigation (design 5c).
    Item {
        id: header
        z: 10
        width: parent.width
        height: headerColumn.implicitHeight

        readonly property bool sessionLive: T3Code.detailSession !== null
            && T3Code.detailSession.status !== "stopped"
        readonly property bool canSnoozeHere: root.thread !== null
            && root.thread.lifecycle === "active" && T3Code.supportsSnooze
        readonly property bool canWakeHere: root.thread !== null
            && root.thread.lifecycle === "snoozed" && T3Code.supportsSnooze
        readonly property bool canSettleHere: root.thread !== null
            && root.thread.lifecycle === "active" && T3Code.supportsSettlement
        readonly property bool canUnsettleHere: root.thread !== null
            && root.thread.lifecycle === "settled" && T3Code.supportsSettlement
        readonly property bool hasMenuItems: sessionLive || canSnoozeHere || canWakeHere
            || canSettleHere || canUnsettleHere

        Column {
            id: headerColumn
            width: parent.width
            spacing: 5

            Item {
                width: parent.width
                height: 34

                IconButton {
                    id: backButton
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "←"
                    onTriggered: root.backRequested()
                }

                Column {
                    anchors.left: backButton.right
                    anchors.leftMargin: 9
                    anchors.right: openButton.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        text: root.thread ? root.thread.title : "Thread"
                        elide: Text.ElideRight
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        font.weight: 600
                        color: Theme.textHi
                    }

                    Text {
                        width: parent.width
                        text: {
                            const parts = [];
                            if (root.thread && root.thread.project !== "")
                                parts.push(root.thread.project);
                            const selection = T3Code.threadSelectionLabel(root.threadId);
                            if (selection !== "")
                                parts.push(selection);
                            return parts.join(" · ");
                        }
                        elide: Text.ElideRight
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        color: Theme.textDim
                    }
                }

                IconButton {
                    id: openButton
                    anchors.right: menuButton.visible ? menuButton.left : parent.right
                    anchors.rightMargin: menuButton.visible ? 6 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "↗"
                    tint: Theme.accent
                    onTriggered: {
                        Quickshell.execDetached(["xdg-open", T3Code.threadUrl(root.threadId)]);
                        Popouts.close();
                    }
                }

                IconButton {
                    id: menuButton
                    visible: header.hasMenuItems
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "⋯"
                    tint: root.menuOpen ? Theme.accent : Theme.textMid
                    onTriggered: root.menuOpen = !root.menuOpen
                }
            }

            Row {
                visible: root.snoozeOpen
                width: parent.width
                spacing: 4

                Repeater {
                    model: T3Code.snoozePresets()
                    delegate: Action {
                        required property var modelData
                        label: modelData.label
                        enabled: T3Code.canDispatch && root.thread !== null && root.thread.canLifecycle
                        onTriggered: {
                            T3Code.snooze(root.threadId, modelData.snoozedUntil);
                            root.snoozeOpen = false;
                        }
                    }
                }
            }
        }

        Rectangle {
            id: overflowMenu
            visible: root.menuOpen && header.hasMenuItems
            z: 100
            anchors.right: parent.right
            y: 32
            width: 164
            height: menuColumn.implicitHeight + 10
            radius: 8
            color: "#1b1c22"
            border.width: 1
            border.color: Theme.popBorder

            Column {
                id: menuColumn
                x: 5
                y: 5
                width: parent.width - 10

                MenuEntry {
                    visible: header.sessionLive
                    label: root.confirmStop ? "Confirm stop session"
                        : T3Code.actionPending("session-stop", root.threadId, "")
                            ? "Stopping…" : "Stop session"
                    tint: root.confirmStop ? Theme.redText : Theme.textMid
                    enabled: T3Code.canDispatch
                        && !T3Code.actionPending("session-stop", root.threadId, "")
                    onTriggered: {
                        if (!root.confirmStop) {
                            root.confirmStop = true;
                            stopConfirmTimer.restart();
                        } else {
                            root.confirmStop = false;
                            root.menuOpen = false;
                            T3Code.stopSession(root.threadId);
                        }
                    }
                }

                MenuEntry {
                    visible: header.canSnoozeHere
                    label: "Snooze…"
                    enabled: T3Code.canDispatch && root.thread !== null && root.thread.canLifecycle
                    onTriggered: {
                        root.menuOpen = false;
                        root.snoozeOpen = true;
                    }
                }

                MenuEntry {
                    visible: header.canWakeHere
                    label: T3Code.actionPending("unsnooze", root.threadId, "")
                        ? "Waking…" : "Wake now"
                    tint: Theme.accent
                    enabled: T3Code.canDispatch
                        && !T3Code.actionPending("unsnooze", root.threadId, "")
                    onTriggered: {
                        root.menuOpen = false;
                        T3Code.unsnooze(root.threadId);
                    }
                }

                MenuEntry {
                    visible: header.canSettleHere
                    label: T3Code.actionPending("settle", root.threadId, "")
                        ? "Settling…" : "Settle"
                    tint: Theme.accent
                    enabled: T3Code.canDispatch && root.thread !== null && root.thread.canLifecycle
                        && !T3Code.actionPending("settle", root.threadId, "")
                    onTriggered: {
                        root.menuOpen = false;
                        T3Code.settle(root.threadId);
                    }
                }

                MenuEntry {
                    visible: header.canUnsettleHere
                    label: T3Code.actionPending("unsettle", root.threadId, "")
                        ? "Unsettling…" : "Unsettle"
                    tint: Theme.accent
                    enabled: T3Code.canDispatch
                        && !T3Code.actionPending("unsettle", root.threadId, "")
                    onTriggered: {
                        root.menuOpen = false;
                        T3Code.unsettle(root.threadId);
                    }
                }
            }
        }
    }

    Timer {
        id: stopConfirmTimer
        interval: 5000
        onTriggered: root.confirmStop = false
    }

    Item {
        id: viewport
        width: parent.width
        height: {
            const room = root.maxHeight - header.height - composer.implicitHeight
                - composerError.implicitHeight - 18;
            return Math.max(140, Math.min(room, timeline.implicitHeight));
        }

        Flickable {
            id: flick
            anchors.fill: parent
            contentWidth: width
            contentHeight: timeline.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            activeFocusOnTab: interactive
            onContentHeightChanged: root.scrollToEnd()
            onHeightChanged: root.scrollToEnd()
            onMovementStarted: root.followTail = false
            onMovementEnded: root.followTail = contentY >= Math.max(0,
                contentHeight - height - 2)

            Column {
                id: timeline
                width: flick.width - (flick.contentHeight > flick.height ? 5 : 0)
                spacing: 6

                Text {
                    visible: T3Code.detailLoading
                    width: parent.width
                    topPadding: 12
                    bottomPadding: 12
                    text: "Loading conversation…"
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    color: Theme.textDim
                }

                InfoCard {
                    visible: T3Code.detailError !== ""
                    heading: "THREAD UNAVAILABLE"
                    body: T3Code.detailError
                    headingColor: Theme.redText
                    fill: Theme.redBgSoft
                    outline: Theme.redBorder
                }

                Action {
                    visible: root.history.hasEarlier
                    anchors.horizontalCenter: parent.horizontalCenter
                    label: "Show " + Math.min(10, root.history.hiddenCount) + " earlier"
                    onTriggered: root.showEarlier()
                }

                Repeater {
                    model: root.history.items
                    delegate: MessageCard { required property var modelData; message: modelData }
                }

                Item {
                    visible: root.working
                    width: parent.width
                    height: 20

                    Row {
                        x: 7
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 7

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: Theme.accent

                            SequentialAnimation on opacity {
                                running: root.working
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 750 }
                                NumberAnimation { to: 1; duration: 750 }
                            }
                        }

                        Text {
                            text: root.workingTime !== ""
                                ? "Working for " + root.workingTime : "Working…"
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            font.weight: 500
                            color: Theme.textLow
                        }
                    }
                }

                Text {
                    visible: !root.working && !T3Code.detailLoading
                        && T3Code.detailMessages.length === 0
                    width: parent.width
                    topPadding: 10
                    bottomPadding: 10
                    text: "No messages yet"
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    color: Theme.textDim
                }

                T3RequestCard {
                    visible: T3Code.detailPendingInputs.length > 0
                    threadId: root.threadId
                    kind: "input"
                    request: T3Code.detailPendingInputs.length > 0
                        ? T3Code.detailPendingInputs[0] : ({ requestId: "", questions: [] })
                    queuedCount: Math.max(0, T3Code.detailPendingInputs.length - 1)
                }

                Repeater {
                    model: T3Code.detailApprovals
                    delegate: T3RequestCard {
                        required property var modelData
                        threadId: root.threadId
                        kind: "approval"
                        request: modelData
                    }
                }

                InfoCard {
                    visible: root.thread !== null && root.thread.pendingInput
                        && !T3Code.detailLoading && T3Code.detailPendingInputs.length === 0
                    heading: "QUESTION"
                    body: "This question needs the full T3 Code client."
                    headingColor: Theme.amber
                    fill: Theme.amberBgSoft
                    outline: Theme.amberBorder
                }

                InfoCard {
                    visible: root.thread !== null && root.thread.pendingApprovals
                        && !T3Code.detailLoading && T3Code.detailApprovals.length === 0
                    heading: "APPROVAL"
                    body: "This approval needs the full T3 Code client."
                    headingColor: Theme.amber
                    fill: Theme.amberBgSoft
                    outline: Theme.amberBorder
                }

                Rectangle {
                    visible: root.plan !== null
                    width: parent.width
                    height: planColumn.implicitHeight + 14
                    radius: 8
                    color: Theme.accentBgSoft
                    border.width: 1
                    border.color: Qt.rgba(158 / 255, 203 / 255, 235 / 255, 0.3)

                    Column {
                        id: planColumn
                        x: 7
                        y: 7
                        width: parent.width - 14
                        spacing: 5

                        Text {
                            width: parent.width
                            text: "READY PLAN"
                            font.family: Theme.fontSans
                            font.pixelSize: 10
                            font.weight: 650
                            font.letterSpacing: 0.7
                            color: Theme.accent
                        }

                        Text {
                            width: parent.width
                            text: root.plan ? root.plan.planMarkdown : ""
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            lineHeight: 1.4
                            maximumLineCount: 14
                            elide: Text.ElideRight
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            color: Theme.textMid
                        }

                        Flow {
                            width: parent.width
                            spacing: 4

                            Action {
                                label: T3Code.actionPending("prompt", root.threadId, "")
                                    ? "Starting…" : "Implement here"
                                enabled: T3Code.canDispatch && root.composerIdle && !root.planTooLong
                                    && !T3Code.actionPending("prompt", root.threadId, "")
                                tint: Theme.accentFg
                                fill: Theme.accent
                                onTriggered: T3Code.implementPlanHere(root.threadId, root.plan)
                            }

                            Action {
                                label: "Refine"
                                enabled: T3Code.canDispatch && root.composerIdle
                                tint: Theme.accent
                                fill: Theme.accentBg
                                onTriggered: {
                                    T3Code.refinePlan(root.threadId);
                                    composer.focusPrompt();
                                }
                            }

                            Action {
                                label: "New thread"
                                enabled: T3Code.canDispatch && T3Code.hasReadyProvider
                                    && T3Code.hasProjects && !root.planTooLong
                                onTriggered: root.newPlanRequested(root.plan)
                            }

                            Action {
                                visible: root.planTooLong
                                label: "Open T3 Code ↗"
                                tint: Theme.accent
                                onTriggered: {
                                    Quickshell.execDetached(["xdg-open", T3Code.threadUrl(root.threadId)]);
                                    Popouts.close();
                                }
                            }
                        }
                    }
                }

                InfoCard {
                    visible: T3Code.detailLatestActivity !== null
                    heading: T3Code.detailLatestActivity
                        && T3Code.detailLatestActivity.tone === "error"
                        ? "LATEST ERROR" : "LATEST ACTIVITY"
                    body: T3Code.detailLatestActivity
                        ? T3Code.detailLatestActivity.summary : ""
                    headingColor: T3Code.detailLatestActivity
                        && T3Code.detailLatestActivity.tone === "error"
                        ? Theme.redText : Theme.textDim
                    fill: T3Code.detailLatestActivity
                        && T3Code.detailLatestActivity.tone === "error"
                        ? Theme.redBgSoft : Theme.cardFill
                    outline: T3Code.detailLatestActivity
                        && T3Code.detailLatestActivity.tone === "error"
                        ? Theme.redBorder : Theme.hairlineSoft
                }

                Rectangle {
                    visible: T3Code.detailCheckpointSummary !== null
                    width: parent.width
                    height: checkpointColumn.implicitHeight + 14
                    radius: 8
                    color: Theme.cardFill
                    border.width: 1
                    border.color: Theme.hairlineSoft

                    Column {
                        id: checkpointColumn
                        x: 7
                        y: 7
                        width: parent.width - 14
                        spacing: 5

                        Item {
                            width: parent.width
                            height: 22

                            Column {
                                anchors.left: parent.left
                                anchors.right: diffAction.left
                                anchors.rightMargin: 5
                                spacing: 1

                                Text {
                                    text: "READY CHECKPOINT"
                                    font.family: Theme.fontSans
                                    font.pixelSize: 9
                                    font.weight: 650
                                    font.letterSpacing: 0.45
                                    color: Theme.textDim
                                }

                                Text {
                                    text: {
                                        const checkpoint = T3Code.detailCheckpointSummary;
                                        return checkpoint ? checkpoint.fileCount + " files · +"
                                            + checkpoint.additions + " −" + checkpoint.deletions : "";
                                    }
                                    font.family: Theme.fontMono
                                    font.pixelSize: 9
                                    color: Theme.textMid
                                }
                            }

                            Action {
                                id: diffAction
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                label: T3Code.detailDiff.loading ? "Loading…"
                                    : T3Code.detailDiff.error !== "" ? "Retry diff" : "View diff"
                                enabled: !T3Code.detailDiff.loading
                                tint: Theme.accent
                                fill: Theme.accentBg
                                onTriggered: T3Code.loadFullThreadDiff(root.threadId,
                                    T3Code.detailCheckpointSummary)
                            }
                        }

                        Text {
                            visible: T3Code.detailCheckpointSummary
                                && T3Code.detailCheckpointSummary.filenames.length > 0
                            width: parent.width
                            text: T3Code.detailCheckpointSummary
                                ? T3Code.detailCheckpointSummary.filenames.join(" · ") : ""
                            elide: Text.ElideMiddle
                            font.family: Theme.fontMono
                            font.pixelSize: 8
                            color: Theme.textDim
                        }

                        Rectangle {
                            visible: T3Code.detailDiff.text !== ""
                            width: parent.width
                            height: 260
                            radius: 6
                            color: Qt.rgba(0, 0, 0, 0.28)
                            border.width: 1
                            border.color: Theme.hairlineSoft

                            Flickable {
                                anchors.fill: parent
                                anchors.margins: 7
                                contentWidth: Math.max(width, patchText.implicitWidth)
                                contentHeight: Math.max(height, patchText.implicitHeight)
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Text {
                                    id: patchText
                                    text: T3Code.detailDiff.text
                                    textFormat: Text.PlainText
                                    wrapMode: Text.NoWrap
                                    font.family: Theme.fontMono
                                    font.pixelSize: 9
                                    color: Theme.textLow
                                }
                            }
                        }

                        Flow {
                            visible: T3Code.detailDiff.text !== "" || T3Code.detailDiff.error !== ""
                            width: parent.width
                            spacing: 4

                            Action {
                                visible: T3Code.detailDiff.text !== ""
                                label: "Copy patch"
                                onTriggered: Quickshell.clipboardText = T3Code.detailDiff.fullText
                            }

                            Text {
                                visible: T3Code.detailDiff.truncated
                                text: "Preview truncated at 100,000 characters / 2,000 lines"
                                font.family: Theme.fontSans
                                font.pixelSize: 9
                                color: Theme.amber
                            }

                            Action {
                                visible: T3Code.detailDiff.truncated
                                label: "Open T3 Code ↗"
                                tint: Theme.accent
                                onTriggered: {
                                    Quickshell.execDetached(["xdg-open", T3Code.threadUrl(root.threadId)]);
                                    Popouts.close();
                                }
                            }
                        }

                        Text {
                            visible: T3Code.detailDiff.error !== ""
                            width: parent.width
                            text: T3Code.detailDiff.error
                            wrapMode: Text.WordWrap
                            font.family: Theme.fontSans
                            font.pixelSize: 9
                            color: Theme.redText
                        }
                    }
                }
            }
        }

        Rectangle {
            visible: flick.contentHeight > flick.height + 1
            anchors.right: parent.right
            width: 2
            height: Math.max(24, viewport.height * flick.visibleArea.heightRatio)
            y: flick.visibleArea.yPosition * viewport.height
            radius: 1
            color: Theme.textFaint
            opacity: flick.moving ? 0.8 : 0.4
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.hairlineSoft
    }

    T3Composer {
        id: composer
        width: parent.width
        threadId: root.threadId
        newThread: false
        editable: root.composerIdle && T3Code.canDispatch
        sendEnabled: root.canCompose && T3Code.canDispatch
        onSendRequested: T3Code.submitExisting(root.threadId, undefined, undefined, null, true)
    }

    Text {
        id: composerError
        visible: text !== ""
        width: parent.width
        text: {
            for (const kind of ["prompt", "interrupt", "session-stop", "settle", "unsettle",
                    "snooze", "unsnooze"]) {
                const error = T3Code.actionError(kind, root.threadId, "");
                if (error !== "")
                    return error;
            }
            return "";
        }
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
        font.family: Theme.fontSans
        font.pixelSize: 10
        color: Theme.redText
    }

    onThreadIdChanged: {
        visibleMessages = 10;
        followTail = true;
        menuOpen = false;
        snoozeOpen = false;
        confirmStop = false;
        T3Code.ensureThreadDraft(threadId);
        if (T3Code.state === "connected")
            T3Code.openDetail(threadId);
    }

    Connections {
        target: T3Code
        function onDetailThreadIdChanged() {
            root.visibleMessages = 10;
            root.followTail = true;
            root.scrollToEnd();
        }
        function onDetailMessagesChanged() { root.scrollToEnd(); }
        function onDetailLoadingChanged() {
            if (!T3Code.detailLoading)
                root.scrollToEnd();
        }
    }

    Component.onCompleted: {
        followTail = true;
        T3Code.ensureThreadDraft(threadId);
        if (T3Code.state === "connected")
            T3Code.openDetail(threadId);
        scrollToEnd();
    }
    Component.onDestruction: T3Code.closeDetail()
}
