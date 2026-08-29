pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

// One full-width conversation surface. Native WebUI history is exposed from
// the header dropdown; the default selection is always the virtual new chat.
Item {
    id: root

    property int maxHeight: 650
    property bool pickerOpen: false
    property bool actionsOpen: false
    property bool confirmDelete: false

    readonly property var conversation: Hermes.selectedConversation
    readonly property var requests: Hermes.selectedRequests
    readonly property var pickerRows: [HermesConversations.newConversation]
        .concat(Hermes.conversations)

    width: parent ? parent.width : 0
    height: maxHeight

    function handleEscape(): bool {
        if (confirmDelete) {
            confirmDelete = false;
            return true;
        }
        if (actionsOpen) {
            actionsOpen = false;
            return true;
        }
        if (pickerOpen) {
            pickerOpen = false;
            return true;
        }
        return false;
    }

    function choose(conversationId) {
        pickerOpen = false;
        actionsOpen = false;
        confirmDelete = false;
        Hermes.selectConversation(conversationId);
    }

    Column {
        id: content
        anchors.fill: parent
        spacing: 5

        Rectangle {
            id: conversationHeader
            width: parent.width
            height: 52
            radius: HermesTheme.panelRadius
            color: HermesTheme.surface
            border.width: 1
            border.color: root.pickerOpen ? HermesTheme.focus : HermesTheme.border
            z: 600

            Rectangle {
                id: pickerButton
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.right: headerActions.left
                anchors.rightMargin: 4
                anchors.top: parent.top
                anchors.topMargin: 4
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                radius: HermesTheme.controlRadius
                color: pickerMouse.containsMouse || activeFocus
                    ? HermesTheme.hover : "transparent"
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "Hermes conversation: "
                    + (root.conversation?.title ?? "New chat")
                Accessible.description: "Open conversation history"
                Accessible.onPressAction: {
                    root.pickerOpen = !root.pickerOpen;
                    root.actionsOpen = false;
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                            || event.key === Qt.Key_Space) {
                        root.pickerOpen = !root.pickerOpen;
                        root.actionsOpen = false;
                        event.accepted = true;
                    }
                }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 7
                    anchors.right: pickerChevron.left
                    anchors.rightMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        text: root.conversation?.title ?? "New chat"
                        elide: Text.ElideRight
                        font.family: HermesTheme.fontUi
                        font.pixelSize: Theme.fontBody
                        font.weight: Theme.weightSemibold
                        color: HermesTheme.textPrimary
                    }

                    Text {
                        width: parent.width
                        text: {
                            if (Hermes.isNewChat)
                                return "Fresh conversation";
                            if (root.conversation?.readOnly === true)
                                return "Read-only history";
                            return root.conversation?.statusText
                                || root.conversation?.model || "Ready";
                        }
                        elide: Text.ElideRight
                        font.family: HermesTheme.fontUi
                        font.pixelSize: Theme.fontCaption
                        color: root.conversation?.status === "attention"
                            ? HermesTheme.amber
                            : root.conversation?.status === "error"
                                ? HermesTheme.red : HermesTheme.textFaint
                    }
                }

                Sym {
                    id: pickerChevron
                    anchors.right: parent.right
                    anchors.rightMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.pickerOpen ? "expand_less" : "expand_more"
                    size: Theme.iconSmall
                    symWeight: 500
                    color: root.pickerOpen ? HermesTheme.accent
                        : HermesTheme.textMuted
                }

                MouseArea {
                    id: pickerMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.pickerOpen = !root.pickerOpen;
                        root.actionsOpen = false;
                        root.confirmDelete = false;
                    }
                }
            }

            Row {
                id: headerActions
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                IconButton {
                    symbol: "add_comment"
                    accessibleName: "New Hermes chat"
                    controlSize: 30
                    tint: Hermes.isNewChat ? HermesTheme.accent
                        : HermesTheme.textMuted
                    enabled: Hermes.canOperate
                    onTriggered: root.choose("")
                }

                IconButton {
                    symbol: "refresh"
                    accessibleName: "Refresh Hermes conversations"
                    controlSize: 30
                    tint: HermesTheme.textMuted
                    enabled: Hermes.connected
                    onTriggered: {
                        HermesConversations.refreshAll();
                        if (!Hermes.isNewChat)
                            HermesConversations.refreshConversation(
                                Hermes.selectedConversationId);
                    }
                }

                IconButton {
                    visible: !Hermes.isNewChat
                    symbol: "more_horiz"
                    accessibleName: "Conversation actions"
                    controlSize: 30
                    tint: root.actionsOpen ? HermesTheme.accent
                        : HermesTheme.textMuted
                    onTriggered: {
                        root.actionsOpen = !root.actionsOpen;
                        root.pickerOpen = false;
                    }
                }
            }

            Rectangle {
                id: pickerPopup
                visible: root.pickerOpen
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.bottom
                anchors.topMargin: 3
                height: Math.min(330, Math.max(58, 10
                    + (root.pickerRows.length > 0 ? 44
                        + Math.max(0, root.pickerRows.length - 1) * 49 : 0)
                    + (Hermes.conversationsLoading
                        || Hermes.conversationsError !== "" ? 39 : 0)))
                radius: HermesTheme.panelRadius
                color: HermesTheme.overlay
                border.width: 1
                border.color: HermesTheme.borderStrong
                clip: true

                ListView {
                    id: pickerList
                    anchors.fill: parent
                    anchors.margins: 5
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    spacing: 1
                    cacheBuffer: 0
                    // A closed dropdown should own no row delegates. When it is
                    // open, ListView creates only the handful inside its 330px
                    // viewport instead of all historical conversations.
                    model: root.pickerOpen ? root.pickerRows : []

                    delegate: Rectangle {
                        id: conversationRow
                        required property var modelData

                        readonly property bool selected:
                            modelData.id === Hermes.selectedConversationId

                        width: pickerList.width
                        height: modelData.id === "" ? 44 : 48
                        radius: HermesTheme.controlRadius
                        color: selected ? HermesTheme.hoverStrong
                            : rowMouse.containsMouse || activeFocus
                                ? HermesTheme.hover : "transparent"
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.id === ""
                            ? "New chat" : "Conversation " + modelData.title
                        Accessible.onPressAction: root.choose(modelData.id)

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return
                                    || event.key === Qt.Key_Enter
                                    || event.key === Qt.Key_Space) {
                                root.choose(conversationRow.modelData.id);
                                event.accepted = true;
                            }
                        }

                        Rectangle {
                            id: statusDot
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: conversationRow.modelData.id === ""
                                ? HermesTheme.accent
                                : conversationRow.modelData.status === "attention"
                                    ? HermesTheme.amber
                                    : conversationRow.modelData.status === "error"
                                        ? HermesTheme.red
                                        : conversationRow.modelData.status === "working"
                                            ? HermesTheme.success
                                            : HermesTheme.textFaint
                        }

                        Column {
                            anchors.left: statusDot.right
                            anchors.leftMargin: 8
                            anchors.right: rowMeta.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                width: parent.width
                                text: conversationRow.modelData.title
                                elide: Text.ElideRight
                                font.family: HermesTheme.fontUi
                                font.pixelSize: Theme.fontCaption
                                font.weight: conversationRow.selected
                                    ? Theme.weightSemibold : Theme.weightMedium
                                color: conversationRow.selected
                                    ? HermesTheme.textPrimary
                                    : HermesTheme.textSecondary
                            }

                            Text {
                                visible: conversationRow.modelData.id !== ""
                                width: parent.width
                                text: [conversationRow.modelData.model,
                                    conversationRow.modelData.source]
                                    .filter(value => value).join(" · ")
                                elide: Text.ElideRight
                                font.family: HermesTheme.fontUi
                                font.pixelSize: Theme.fontMicro
                                color: HermesTheme.textFaint
                            }
                        }

                        Text {
                            id: rowMeta
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 58
                            horizontalAlignment: Text.AlignRight
                            text: conversationRow.modelData.id === ""
                                ? "NEW" : Hermes.relativeTime(
                                    conversationRow.modelData.updatedAt)
                            font.family: HermesTheme.fontUi
                            font.pixelSize: Theme.fontMicro
                            font.features: HermesTheme.tabularNumberFeatures
                            color: conversationRow.modelData.id === ""
                                ? HermesTheme.accent : HermesTheme.textFaint
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.choose(conversationRow.modelData.id)
                        }
                    }

                    footer: Text {
                        visible: Hermes.conversationsLoading
                            || Hermes.conversationsError !== ""
                        width: pickerList.width
                        height: visible ? 38 : 0
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: Hermes.conversationsLoading
                            ? "Loading history…" : Hermes.conversationsError
                        elide: Text.ElideRight
                        font.family: HermesTheme.fontUi
                        font.pixelSize: Theme.fontCaption
                        color: Hermes.conversationsError !== ""
                            ? HermesTheme.red : HermesTheme.textFaint
                    }
                }

                ScrollChrome { target: pickerList }
            }

            Rectangle {
                id: actionsPopup
                visible: root.actionsOpen && !Hermes.isNewChat
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.top: parent.bottom
                anchors.topMargin: 3
                width: Math.min(220, conversationHeader.width - 8)
                height: actionsColumn.implicitHeight + 10
                radius: HermesTheme.panelRadius
                color: HermesTheme.overlay
                border.width: 1
                border.color: HermesTheme.borderStrong

                component Entry: Rectangle {
                    id: entry
                    property string label: ""
                    property string symbol: ""
                    property color tint: HermesTheme.textSecondary
                    property bool actionEnabled: true
                    signal triggered()
                    width: parent ? parent.width : 0
                    height: 34
                    radius: HermesTheme.controlRadius
                    color: entryMouse.containsMouse && actionEnabled
                        ? HermesTheme.hoverStrong : "transparent"
                    opacity: actionEnabled ? 1 : 0.38
                    Accessible.role: Accessible.Button
                    Accessible.name: label
                    Accessible.onPressAction: {
                        if (actionEnabled)
                            triggered();
                    }

                    Sym {
                        id: entryIcon
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        name: entry.symbol
                        size: Theme.iconSmall
                        symWeight: 450
                        color: entry.tint
                    }
                    Text {
                        anchors.left: entryIcon.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.label
                        elide: Text.ElideRight
                        font.family: HermesTheme.fontUi
                        font.pixelSize: Theme.fontCaption
                        color: entry.tint
                    }
                    MouseArea {
                        id: entryMouse
                        anchors.fill: parent
                        enabled: entry.actionEnabled
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor
                            : Qt.ForbiddenCursor
                        onClicked: entry.triggered()
                    }
                }

                Column {
                    id: actionsColumn
                    x: 5
                    y: 5
                    width: parent.width - 10
                    spacing: 1

                    Entry {
                        label: "Compress context"
                        symbol: "compress"
                        actionEnabled: root.conversation?.readOnly !== true
                        onTriggered: {
                            root.actionsOpen = false;
                            Hermes.compress(Hermes.selectedConversationId);
                        }
                    }
                    Entry {
                        label: root.confirmDelete
                            ? "Confirm delete" : "Delete conversation"
                        symbol: "delete"
                        tint: HermesTheme.red
                        actionEnabled: root.conversation?.readOnly !== true
                        onTriggered: {
                            if (!root.confirmDelete) {
                                root.confirmDelete = true;
                                return;
                            }
                            root.actionsOpen = false;
                            root.confirmDelete = false;
                            Hermes.deleteConversation(
                                Hermes.selectedConversationId);
                        }
                    }
                }
            }
        }

        HermesTranscript {
            id: transcript
            width: parent.width
            conversationId: Hermes.selectedConversationId
            maxHeight: Math.max(150, content.height - conversationHeader.height
                - requestArea.height - composer.height - content.spacing * 3)
        }

        Column {
            id: requestArea
            visible: root.requests.length > 0
            width: parent.width
            height: visible ? implicitHeight : 0
            spacing: 4

            Text {
                visible: root.requests.length > 1
                width: parent.width
                text: "1 shown · " + (root.requests.length - 1) + " more queued"
                horizontalAlignment: Text.AlignRight
                font.family: HermesTheme.fontUi
                font.pixelSize: Theme.fontMicro
                color: HermesTheme.textFaint
            }

            Repeater {
                model: root.requests.length > 0 ? [root.requests[0]] : []
                delegate: HermesRequestCard {
                    required property var modelData
                    width: parent.width
                    conversationId: Hermes.selectedConversationId
                    request: modelData
                }
            }
        }

        HermesComposer {
            id: composer
            width: parent.width
            conversationId: Hermes.selectedConversationId
        }
    }
}
