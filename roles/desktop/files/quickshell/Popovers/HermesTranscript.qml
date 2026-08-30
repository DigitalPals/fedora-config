pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../Common"
import "../Common/HermesHelpers.js" as Helpers

// The transcript is prose-only. Tool protocol records are projected away from
// chat and collapsed into one ephemeral activity line that follows the newest
// call while Hermes is working.
Item {
    id: root

    required property string conversationId
    property int maxHeight: 390
    property int visibleItems: 50
    property bool followTail: true
    property bool stateExpanded: false
    property real pendingPrependHeight: -1

    readonly property var conversation: conversationId === ""
        ? HermesConversations.newConversation
        : HermesConversations.conversationById(conversationId)
    readonly property var allMessages: HermesConversations.messagesFor(conversationId)
    readonly property var allTools: HermesConversations.toolsFor(conversationId)
    readonly property var allItems: Helpers.transcriptItems(allMessages, [])
    readonly property int hiddenCount: Math.max(0, allItems.length - visibleItems)
    readonly property var shownItems: hiddenCount > 0
        ? allItems.slice(hiddenCount) : allItems
    readonly property var history: HermesConversations.historyFor(conversationId)
    readonly property var sessionState: HermesConversations.sessionStateFor(conversationId)
    readonly property var latestTool: allTools.length > 0
        ? allTools[allTools.length - 1] : null
    readonly property bool working: conversation !== null
        && conversation.status === "working"
    readonly property bool hasSessionState: sessionState.warning !== ""
        || sessionState.goalMessage !== "" || sessionState.todos.length > 0
        || sessionState.pendingSteer !== "" || sessionState.background !== ""
        || sessionState.reasoning !== "" || Object.keys(sessionState.context).length > 0
        || Object.keys(sessionState.usage).length > 0

    width: parent ? parent.width : 0
    height: maxHeight

    function scrollToEnd(force) {
        if (!followTail && force !== true)
            return;
        Qt.callLater(() => {
            if (root.followTail || force === true)
                transcriptFlick.contentY = Math.max(0,
                    transcriptFlick.contentHeight - transcriptFlick.height);
        });
    }

    function showEarlier() {
        followTail = false;
        if (hiddenCount > 0) {
            const oldHeight = transcriptFlick.contentHeight;
            visibleItems += 50;
            Qt.callLater(() => {
                transcriptFlick.contentY = Math.max(0, transcriptFlick.contentY
                    + transcriptFlick.contentHeight - oldHeight);
            });
            return;
        }
        if (history.hasMore === true && history.loadingEarlier !== true) {
            pendingPrependHeight = transcriptFlick.contentHeight;
            HermesConversations.loadEarlier(conversationId);
        }
    }

    function compactNumber(value) {
        const amount = Number(value) || 0;
        if (amount >= 1000000)
            return (amount / 1000000).toFixed(amount >= 10000000 ? 0 : 1) + "m";
        if (amount >= 1000)
            return (amount / 1000).toFixed(amount >= 10000 ? 0 : 1) + "k";
        return String(Math.max(0, Math.round(amount)));
    }

    function stateSummary() {
        const state = sessionState;
        if (state.warning !== "")
            return state.warning;
        if (state.pendingSteer !== "")
            return "Steering saved for the next turn";
        if (state.goalMessage !== "")
            return state.goalMessage;
        const summary = state.todoSummary ?? ({});
        const total = Number(summary.total) || state.todos.length;
        if (total > 0)
            return String(Number(summary.completed) || 0) + " of " + total
                + " tasks complete";
        const context = state.context ?? ({});
        const used = Number(context.lastPromptTokens ?? context.last_prompt_tokens) || 0;
        const length = Number(context.contextLength ?? context.context_length) || 0;
        if (used > 0 && length > 0)
            return "Context " + Math.min(100, Math.round(used / length * 100)) + "%";
        const usage = state.usage ?? ({});
        const tokens = Number(usage.total_tokens)
            || Number(usage.input_tokens) + Number(usage.output_tokens);
        if (tokens > 0)
            return compactNumber(tokens) + " tokens this turn";
        if (state.reasoningActive)
            return "Hermes is reasoning…";
        if (state.reasoning !== "")
            return "Reasoning available";
        return state.background;
    }

    onConversationIdChanged: {
        visibleItems = 50;
        followTail = true;
        stateExpanded = false;
        pendingPrependHeight = -1;
        scrollToEnd(true);
    }
    onHeightChanged: scrollToEnd(false)

    Connections {
        target: HermesConversations
        function onTranscriptChanged(changedConversationId) {
            if (changedConversationId !== root.conversationId)
                return;
            if (root.pendingPrependHeight >= 0) {
                const oldHeight = root.pendingPrependHeight;
                root.pendingPrependHeight = -1;
                Qt.callLater(() => {
                    transcriptFlick.contentY = Math.max(0,
                        transcriptFlick.contentY + transcriptFlick.contentHeight - oldHeight);
                });
                return;
            }
            root.scrollToEnd(false);
        }
        function onToolsByConversationChanged() { root.scrollToEnd(false); }
    }

    Flickable {
        id: transcriptFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: transcriptColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onMovementEnded: root.followTail = contentY + height >= contentHeight - 36

        Column {
            id: transcriptColumn
            width: transcriptFlick.width
            spacing: 5

            ActionButton {
                visible: root.hiddenCount > 0 || root.history.hasMore === true
                    || root.history.loadingEarlier === true
                anchors.horizontalCenter: parent.horizontalCenter
                label: root.history.loadingEarlier ? "Loading earlier history…"
                    : root.hiddenCount > 0
                        ? "Show " + Math.min(50, root.hiddenCount) + " earlier"
                        : "Load earlier history"
                enabled: root.history.loadingEarlier !== true
                fontFamily: HermesTheme.fontUi
                focusColor: HermesTheme.focus
                buttonRadius: HermesTheme.controlRadius
                tint: HermesTheme.textMuted
                fill: HermesTheme.hover
                onTriggered: root.showEarlier()
            }

            Rectangle {
                id: sessionStateCard
                visible: root.hasSessionState
                width: parent.width
                height: visible ? stateColumn.implicitHeight + 12 : 0
                radius: HermesTheme.rowRadius
                color: root.sessionState.warning !== ""
                    ? HermesTheme.redSoft : HermesTheme.accentSubtle
                border.width: 1
                border.color: root.sessionState.warning !== ""
                    ? HermesTheme.redBorder : HermesTheme.border
                activeFocusOnTab: root.sessionState.reasoning !== ""
                Accessible.role: Accessible.Button
                Accessible.name: root.stateSummary()
                Accessible.onPressAction: {
                    if (root.sessionState.reasoning !== "")
                        root.stateExpanded = !root.stateExpanded;
                }

                Keys.onPressed: event => {
                    if (root.sessionState.reasoning !== ""
                            && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                || event.key === Qt.Key_Space)) {
                        root.stateExpanded = !root.stateExpanded;
                        event.accepted = true;
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.sessionState.reasoning !== ""
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.stateExpanded = !root.stateExpanded
                }

                Column {
                    id: stateColumn
                    x: 8
                    y: 6
                    width: parent.width - 16
                    spacing: 5

                    Row {
                        width: parent.width
                        spacing: 7

                        Sym {
                            name: root.sessionState.warning !== "" ? "warning"
                                : root.sessionState.goalMessage !== "" ? "flag"
                                    : root.sessionState.todos.length > 0 ? "checklist"
                                        : root.sessionState.reasoningActive
                                            ? "psychology" : "info"
                            size: Theme.iconSmall
                            symWeight: 460
                            color: root.sessionState.warning !== ""
                                ? HermesTheme.red : HermesTheme.accent
                        }

                        Text {
                            width: parent.width - 42
                            text: root.stateSummary()
                            elide: Text.ElideRight
                            font.family: HermesTheme.fontUi
                            font.pixelSize: Theme.fontCaption
                            color: root.sessionState.warning !== ""
                                ? HermesTheme.red : HermesTheme.textSecondary
                        }

                        Sym {
                            visible: root.sessionState.reasoning !== ""
                            name: root.stateExpanded ? "expand_less" : "expand_more"
                            size: Theme.iconSmall
                            color: HermesTheme.textFaint
                        }
                    }

                    Text {
                        visible: root.stateExpanded && root.sessionState.reasoning !== ""
                        width: parent.width
                        text: root.sessionState.reasoning
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        maximumLineCount: 16
                        elide: Text.ElideRight
                        font.family: HermesTheme.fontMono
                        font.pixelSize: Theme.fontMicro
                        color: HermesTheme.textFaint
                    }
                }
            }

            Repeater {
                model: root.shownItems

                delegate: Item {
                    id: timelineRow
                    required property var modelData
                    required property int index

                    readonly property var message: modelData.message ?? ({})
                    readonly property string messageText: String(message.text ?? "")
                    readonly property bool fromUser: message.role === "user"
                    readonly property bool fromSystem: message.role === "system"
                    readonly property bool continuation: index > 0
                        && root.shownItems[index - 1].message.role === message.role
                    readonly property bool hovered: messageHover.hovered || activeFocus

                    width: parent.width
                    height: messageColumn.implicitHeight + 12
                    activeFocusOnTab: true
                    Accessible.role: Accessible.StaticText
                    Accessible.name: (fromUser ? "You"
                        : fromSystem ? "System" : "Hermes") + ": "
                        + (messageText || "working")

                    HoverHandler { id: messageHover }

                    Rectangle {
                        anchors.top: parent.top
                        x: 2
                        width: parent.width - 4
                        height: 1
                        color: HermesTheme.border
                    }

                    Column {
                        id: messageColumn
                        x: 3
                        y: 8
                        width: parent.width - 6
                        spacing: 5

                        Item {
                            width: parent.width
                            height: Theme.sectionHeaderHeight

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !timelineRow.continuation
                                text: timelineRow.fromUser ? "YOU"
                                    : timelineRow.fromSystem ? "SYSTEM" : "HERMES"
                                font.family: HermesTheme.fontUi
                                font.pixelSize: Theme.fontMicro
                                font.weight: Theme.weightSemibold
                                font.letterSpacing: 1
                                color: timelineRow.fromUser || timelineRow.fromSystem
                                    ? HermesTheme.textFaint : HermesTheme.accent
                            }

                            IconButton {
                                id: copyButton
                                visible: timelineRow.hovered
                                anchors.right: messageTime.left
                                anchors.rightMargin: 2
                                anchors.verticalCenter: parent.verticalCenter
                                controlSize: Theme.chipInnerHeight
                                symbol: "content_copy"
                                accessibleName: "Copy message"
                                tint: HermesTheme.textFaint
                                onTriggered: Quickshell.clipboardText =
                                    timelineRow.messageText
                            }

                            Text {
                                id: messageTime
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: timelineRow.message.streaming ? "streaming…"
                                    : Hermes.relativeTime(timelineRow.message.updatedAt
                                        || timelineRow.message.createdAt)
                                font.family: HermesTheme.fontUi
                                font.pixelSize: Theme.fontMicro
                                font.features: HermesTheme.tabularNumberFeatures
                                color: HermesTheme.textFaint
                            }
                        }

                        Text {
                            width: parent.width
                            text: timelineRow.messageText !== ""
                                ? timelineRow.messageText
                                : timelineRow.message.streaming ? "Hermes is working…" : ""
                            textFormat: timelineRow.fromUser
                                ? Text.PlainText : Text.MarkdownText
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            lineHeight: Theme.proseLineHeight
                            font.family: HermesTheme.fontUi
                            font.pixelSize: Theme.fontSecondary
                            color: timelineRow.message.error !== ""
                                ? HermesTheme.red
                                : timelineRow.fromUser ? HermesTheme.textPrimary
                                    : HermesTheme.textSecondary
                            onLinkActivated: link => Hermes.openExternalUrl(link)
                        }
                    }
                }
            }

            HermesToolCard {
                id: toolActivity
                visible: root.working && root.latestTool !== null
                width: parent.width
                height: visible ? implicitHeight : 0
                tool: root.latestTool ?? ({})
            }

            Rectangle {
                id: workingCard
                visible: root.working && root.latestTool === null
                    && !root.allMessages.some(message => message.streaming)
                width: parent.width
                height: 34
                radius: HermesTheme.rowRadius
                color: Theme.chip
                border.width: 1
                border.color: HermesTheme.border

                Sym {
                    id: workingGlyph
                    x: 9
                    anchors.verticalCenter: parent.verticalCenter
                    name: "progress_activity"
                    size: Theme.iconSmall
                    symWeight: 430
                    color: HermesTheme.accent

                    RotationAnimation on rotation {
                        running: workingCard.visible && !Theme.reducedMotion
                        from: 0
                        to: 360
                        loops: Animation.Infinite
                        duration: 950
                    }
                }

                Text {
                    anchors.left: workingGlyph.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.conversation?.statusText || "Hermes is working…"
                    elide: Text.ElideRight
                    font.family: HermesTheme.fontUi
                    font.pixelSize: Theme.fontCaption
                    color: HermesTheme.textSecondary
                }
            }

            StatusPlaceholder {
                visible: root.allItems.length === 0 && !root.hasSessionState
                    && !root.working
                width: parent.width
                kind: HermesConversations.selectedLoading ? "loading"
                    : Hermes.selectedError !== "" ? "error" : "empty"
                title: HermesConversations.selectedLoading ? "Loading conversation…"
                    : Hermes.selectedError !== "" ? Hermes.selectedError
                        : root.conversationId === "" ? "Start a new chat"
                            : "No messages yet"
                detail: HermesConversations.selectedLoading || Hermes.selectedError !== ""
                    ? "" : root.conversationId === ""
                        ? "Your first message creates a fresh Hermes conversation."
                        : "Continue this historical conversation with its existing context."
                fontFamily: HermesTheme.fontUi
                accentColor: HermesTheme.accent
                accentFill: HermesTheme.accentSubtle
                outlineColor: HermesTheme.border
                primaryTextColor: HermesTheme.textSecondary
                secondaryTextColor: HermesTheme.textFaint
                errorColor: HermesTheme.red
                errorFill: HermesTheme.redSoft
                errorOutline: HermesTheme.redBorder
            }
        }
    }

    ScrollChrome {
        target: transcriptFlick
    }
}
