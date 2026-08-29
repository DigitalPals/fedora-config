import QtQuick
import "../Common"

// Persistent per-conversation composer. Enter sends, Shift/Ctrl+Enter adds a line,
// slash commands travel through Hermes' slash worker/dispatcher pipeline, and a live turn swaps the
// primary action to Stop without discarding the next draft.
Rectangle {
    id: root

    required property string conversationId
    readonly property var conversation: conversationId === ""
        ? HermesConversations.newConversation
        : HermesConversations.conversationById(conversationId)
    readonly property bool working: conversation !== null && conversation.status === "working"
    readonly property bool blocked: conversation !== null && conversation.status === "attention"
    readonly property bool sending: Hermes.actionPending("prompt", conversationId, "")
        || conversationId === ""
            && Hermes.actionPending("conversation-create", "", "")
        || Hermes.actionKindPending("command", conversationId)
    readonly property bool stopping: Hermes.actionPending("interrupt", conversationId, "")
    readonly property bool steering: Hermes.actionPending("steer", conversationId, "")
    readonly property bool editable: Hermes.canOperate && conversation !== null
        && conversation.readOnly !== true && !sending
    readonly property bool overLimit: promptEdit.text.length > 120000

    width: parent ? parent.width : 0
    height: composerContent.implicitHeight + 18
    radius: HermesTheme.panelRadius
    color: HermesTheme.composer
    border.width: 1
    border.color: overLimit ? HermesTheme.redBorder
        : promptEdit.activeFocus ? HermesTheme.focus : HermesTheme.borderStrong

    Behavior on border.color {
        ColorAnimation { duration: HermesTheme.fastDuration }
    }

    function syncDraft() {
        const next = Hermes.draft(conversationId);
        if (promptEdit.text === next)
            return;
        promptEdit.syncing = true;
        promptEdit.text = next;
        promptEdit.cursorPosition = next.length;
        promptEdit.syncing = false;
    }

    function insertNewline() {
        const start = promptEdit.selectionStart;
        const end = promptEdit.selectionEnd;
        if (start !== end) {
            promptEdit.remove(start, end);
            promptEdit.cursorPosition = start;
        }
        const position = promptEdit.cursorPosition;
        promptEdit.insert(position, "\n");
        promptEdit.cursorPosition = position + 1;
    }

    function send() {
        if (!editable || overLimit || promptEdit.text.trim() === "")
            return;
        Hermes.submit(conversationId, promptEdit.text);
    }

    function steer() {
        if (!root.working || root.steering || promptEdit.text.trim() === "")
            return;
        Hermes.steer(conversationId, promptEdit.text);
    }

    function focusPrompt() {
        promptEdit.forceActiveFocus();
        promptEdit.cursorPosition = promptEdit.text.length;
    }

    onConversationIdChanged: syncDraft()
    Component.onCompleted: syncDraft()

    Connections {
        target: HermesConversations
        function onDraftsChanged() { root.syncDraft(); }
    }

    Column {
        id: composerContent
        x: 9
        y: 9
        width: parent.width - 18
        spacing: 7

        Item {
            width: parent.width
            height: Math.max(54, Math.min(116, promptEdit.contentHeight + 6))

            Flickable {
                id: promptFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: Math.max(height, promptEdit.contentHeight)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                TextEdit {
                    id: promptEdit
                    property bool syncing: false

                    width: promptFlick.width
                    height: Math.max(promptFlick.height, contentHeight)
                    enabled: root.editable
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    Accessible.name: "Message Hermes in "
                        + (root.conversation?.title ?? "new chat")
                    Accessible.description: "Enter sends. Shift Enter inserts a newline."
                    font.family: HermesTheme.fontUi
                    font.pixelSize: Theme.fontBody
                    color: HermesTheme.textPrimary
                    selectionColor: HermesTheme.accentSoft
                    selectedTextColor: HermesTheme.textPrimary
                    onTextChanged: {
                        if (!syncing && activeFocus)
                            Hermes.setDraft(root.conversationId, text);
                    }
                    onCursorRectangleChanged: {
                        if (cursorRectangle.y + cursorRectangle.height
                                > promptFlick.contentY + promptFlick.height)
                            promptFlick.contentY = cursorRectangle.y
                                + cursorRectangle.height - promptFlick.height;
                        else if (cursorRectangle.y < promptFlick.contentY)
                            promptFlick.contentY = cursorRectangle.y;
                    }

                    Keys.onPressed: event => {
                        if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                            return;
                        if (event.modifiers & Qt.ShiftModifier
                                || event.modifiers & Qt.ControlModifier)
                            root.insertNewline();
                        else
                            root.send();
                        event.accepted = true;
                    }

                    Text {
                        visible: promptEdit.text === ""
                        text: root.conversation?.readOnly === true
                            ? "This conversation is read-only"
                            : root.blocked ? "Answer Hermes above…"
                            : !Hermes.connected ? "Hermes bridge is offline"
                                : !Hermes.bridgeReady ? "Waiting for Hermes…"
                                    : root.conversationId === ""
                                        ? "Message Hermes…"
                                        : "Continue this conversation…"
                        font.family: HermesTheme.fontUi
                        font.pixelSize: Theme.fontBody
                        color: HermesTheme.textFaint
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: Theme.inlineActionHeight

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.conversation?.model || "Hermes"
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 150)
                    font.family: HermesTheme.fontUi
                    font.pixelSize: Theme.fontCaption
                    color: HermesTheme.textFaint
                }

                Text {
                    visible: promptEdit.text.startsWith("/")
                    anchors.verticalCenter: parent.verticalCenter
                    text: "command"
                    font.family: HermesTheme.fontUi
                    font.pixelSize: Theme.fontMicro
                    color: HermesTheme.accent
                }

                Text {
                    visible: root.overLimit
                    anchors.verticalCenter: parent.verticalCenter
                    text: promptEdit.text.length + "/120000"
                    font.family: HermesTheme.fontMono
                    font.pixelSize: Theme.fontMicro
                    color: HermesTheme.red
                }
            }

            Text {
                id: activityText
                visible: root.working || root.sending
                anchors.right: steerButton.visible ? steerButton.left : primaryButton.left
                anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(150, implicitWidth)
                text: root.sending ? "sending…"
                    : (root.conversation?.statusText || "Hermes is working…")
                elide: Text.ElideRight
                font.family: HermesTheme.fontUi
                font.pixelSize: Theme.fontMicro
                color: HermesTheme.textFaint
            }

            ActionButton {
                id: steerButton
                visible: root.working && promptEdit.text.trim() !== ""
                anchors.right: primaryButton.left
                anchors.rightMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                label: root.steering ? "Steering…" : "Steer"
                enabled: !root.steering
                fontFamily: HermesTheme.fontUi
                focusColor: HermesTheme.focus
                buttonRadius: HermesTheme.controlRadius
                tint: HermesTheme.accent
                fill: HermesTheme.accentSubtle
                onTriggered: root.steer()
            }

            Rectangle {
                id: primaryButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.inlineActionHeight
                height: width
                radius: HermesTheme.controlRadius
                color: root.working
                    ? (primaryMouse.containsMouse ? HermesTheme.red : HermesTheme.redSoft)
                    : (primaryMouse.containsMouse ? HermesTheme.accentHover
                        : HermesTheme.accent)
                opacity: primaryMouse.enabled ? 1 : 0.35
                activeFocusOnTab: primaryMouse.enabled
                border.width: activeFocus ? 1 : 0
                border.color: HermesTheme.focus
                Accessible.role: Accessible.Button
                Accessible.name: root.working ? "Stop Hermes" : "Send to Hermes"
                Accessible.onPressAction: {
                    if (root.working)
                        Hermes.interrupt(root.conversationId);
                    else
                        root.send();
                }

                Keys.onPressed: event => {
                    if (!primaryMouse.enabled)
                        return;
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                            || event.key === Qt.Key_Space) {
                        if (root.working)
                            Hermes.interrupt(root.conversationId);
                        else
                            root.send();
                        event.accepted = true;
                    }
                }

                Sym {
                    anchors.centerIn: parent
                    name: root.stopping || root.sending ? "more_horiz"
                        : root.working ? "stop" : "arrow_upward"
                    size: Theme.iconMedium
                    fill: root.working ? 1 : 0
                    symWeight: 520
                    color: root.working && !primaryMouse.containsMouse
                        ? HermesTheme.red : HermesTheme.accentForeground
                }

                MouseArea {
                    id: primaryMouse
                    anchors.fill: parent
                    enabled: root.working ? !root.stopping
                        : root.editable && !root.overLimit
                            && promptEdit.text.trim() !== ""
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.working)
                            Hermes.interrupt(root.conversationId);
                        else
                            root.send();
                    }
                }
            }
        }
    }
}
