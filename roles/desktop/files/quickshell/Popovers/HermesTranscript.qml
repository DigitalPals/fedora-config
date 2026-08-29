pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../Common"

// Streaming transcript with compact tool lifecycle cards. A conversation retains
// up to 250 normalized messages; the view reveals older turns in batches and
// follows the tail until the user deliberately scrolls away.
Item {
    id: root

    required property string conversationId
    property int maxHeight: 390
    property int visibleMessages: 40
    property bool followTail: true

    readonly property var conversation: conversationId === ""
        ? HermesConversations.newConversation
        : HermesConversations.conversationById(conversationId)
    readonly property var allMessages: HermesConversations.messagesFor(conversationId)
    readonly property int hiddenCount: Math.max(0, allMessages.length - visibleMessages)
    readonly property var shownMessages: hiddenCount > 0
        ? allMessages.slice(hiddenCount) : allMessages
    readonly property var allTools: HermesConversations.toolsFor(conversationId)
    readonly property var shownTools: {
        const running = allTools.filter(tool => !tool.terminal);
        const finished = allTools.filter(tool => tool.terminal).slice(-4);
        return finished.concat(running.filter(tool =>
            !finished.some(item => item.id === tool.id)));
    }
    readonly property bool working: conversation !== null && conversation.status === "working"

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
        const oldHeight = transcriptFlick.contentHeight;
        visibleMessages += 40;
        Qt.callLater(() => {
            transcriptFlick.contentY = Math.max(0, transcriptFlick.contentY
                + transcriptFlick.contentHeight - oldHeight);
        });
    }

    onConversationIdChanged: {
        visibleMessages = 40;
        followTail = true;
        scrollToEnd(true);
    }
    onHeightChanged: scrollToEnd(false)

    Connections {
        target: HermesConversations
        function onTranscriptChanged(changedConversationId) {
            if (changedConversationId === root.conversationId)
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
                visible: root.hiddenCount > 0
                anchors.horizontalCenter: parent.horizontalCenter
                label: "Show " + Math.min(40, root.hiddenCount) + " earlier"
                fontFamily: HermesTheme.fontUi
                focusColor: HermesTheme.focus
                buttonRadius: HermesTheme.controlRadius
                tint: HermesTheme.textMuted
                fill: HermesTheme.hover
                onTriggered: root.showEarlier()
            }

            Repeater {
                model: root.shownMessages

                delegate: Item {
                    id: messageCard
                    required property var modelData
                    required property int index

                    readonly property bool fromUser: modelData.role === "user"
                    readonly property bool fromSystem: modelData.role === "system"
                    readonly property bool continuation: index > 0
                        && root.shownMessages[index - 1].role === modelData.role
                    readonly property bool hovered: messageHover.hovered || activeFocus

                    width: parent.width
                    height: messageColumn.implicitHeight + 12
                    activeFocusOnTab: true
                    Accessible.role: Accessible.StaticText
                    Accessible.name: (fromUser ? "You"
                        : fromSystem ? "System" : "Hermes") + ": "
                        + (modelData.text || "working")

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
                                visible: !messageCard.continuation
                                text: messageCard.fromUser ? "YOU"
                                    : messageCard.fromSystem ? "SYSTEM" : "HERMES"
                                font.family: HermesTheme.fontUi
                                font.pixelSize: Theme.fontMicro
                                font.weight: Theme.weightSemibold
                                font.letterSpacing: 1
                                color: messageCard.fromUser || messageCard.fromSystem
                                    ? HermesTheme.textFaint : HermesTheme.accent
                            }

                            IconButton {
                                id: copyButton
                                visible: messageCard.hovered
                                anchors.right: messageTime.left
                                anchors.rightMargin: 2
                                anchors.verticalCenter: parent.verticalCenter
                                controlSize: Theme.chipInnerHeight
                                symbol: "content_copy"
                                accessibleName: "Copy message"
                                tint: HermesTheme.textFaint
                                onTriggered: Quickshell.clipboardText =
                                    messageCard.modelData.text ?? ""
                            }

                            Text {
                                id: messageTime
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: messageCard.modelData.streaming ? "streaming…"
                                    : Hermes.relativeTime(messageCard.modelData.updatedAt
                                        || messageCard.modelData.createdAt)
                                font.family: HermesTheme.fontUi
                                font.pixelSize: Theme.fontMicro
                                font.features: HermesTheme.tabularNumberFeatures
                                color: HermesTheme.textFaint
                            }
                        }

                        Text {
                            width: parent.width
                            text: messageCard.modelData.text !== ""
                                ? messageCard.modelData.text
                                : messageCard.modelData.streaming ? "Hermes is working…" : ""
                            textFormat: messageCard.fromUser
                                ? Text.PlainText : Text.MarkdownText
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            lineHeight: Theme.proseLineHeight
                            font.family: HermesTheme.fontUi
                            font.pixelSize: Theme.fontSecondary
                            color: messageCard.modelData.error !== ""
                                ? HermesTheme.red
                                : messageCard.fromUser ? HermesTheme.textPrimary
                                    : HermesTheme.textSecondary
                            onLinkActivated: link => Hermes.openExternalUrl(link)
                        }
                    }
                }
            }

            Column {
                visible: root.shownTools.length > 0
                width: parent.width
                spacing: 4

                Repeater {
                    model: root.shownTools

                    delegate: HermesToolCard {
                        required property var modelData
                        width: parent.width
                        tool: modelData
                    }
                }
            }

            Rectangle {
                id: workingCard
                visible: root.working && root.shownTools.length === 0
                    && !root.shownMessages.some(message => message.streaming)
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
                visible: root.allMessages.length === 0 && root.shownTools.length === 0
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
