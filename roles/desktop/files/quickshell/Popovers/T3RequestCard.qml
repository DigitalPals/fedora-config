import QtQuick
import "../Common"

// Compact approval or structured-question card. Question answers and paging
// live in T3Code, so rejected requests remain intact across navigation.
Rectangle {
    id: root

    required property string threadId
    required property string kind // "approval" | "input"
    required property var request
    property int queuedCount: 0

    readonly property bool isInput: kind === "input"
    readonly property var questions: isInput && Array.isArray(request.questions)
        ? request.questions : []
    readonly property int storedIndex: isInput
        ? T3Code.inputQuestionIndex(threadId, request.requestId) : 0
    readonly property int questionIndex: questions.length > 0
        ? Math.max(0, Math.min(storedIndex, questions.length - 1)) : 0
    readonly property var question: questions.length > 0 ? questions[questionIndex] : null
    readonly property bool pending: T3Code.actionPending(kind, threadId, request.requestId)
    readonly property bool actionable: T3Code.canDispatch && !pending
    readonly property string failure: T3Code.actionError(kind, threadId, request.requestId)
    readonly property bool answered: question !== null
        && T3Code.inputQuestionAnswered(threadId, request.requestId, question)
    readonly property var answers: isInput ? T3Code.buildInputAnswers(threadId, request) : null

    width: parent ? parent.width : 0
    height: content.implicitHeight + 14
    radius: 8
    color: Theme.amberBgSoft
    border.width: 1
    border.color: Theme.amberBorder

    component Action: Rectangle {
        id: action
        property string label: ""
        property color tint: Theme.textMid
        property color fill: Theme.hoverFill
        signal triggered()

        width: actionText.implicitWidth + 16
        height: 23
        radius: 6
        color: actionMouse.containsMouse && enabled ? Qt.lighter(fill, 1.2) : fill
        opacity: enabled ? 1 : 0.45
        activeFocusOnTab: enabled
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
            id: actionText
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

    Column {
        id: content
        x: 7
        y: 7
        width: parent.width - 14
        spacing: 7

        Item {
            width: parent.width
            height: 16

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.isInput && root.question
                    ? root.question.header.toUpperCase()
                    : root.request.kind === "file-change" ? "EDIT APPROVAL"
                    : root.request.kind === "file-read" ? "READ APPROVAL" : "COMMAND APPROVAL"
                font.family: Theme.fontSans
                font.pixelSize: 9
                font.weight: 650
                font.letterSpacing: 0.5
                color: Theme.amber
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.isInput ? (root.questionIndex + 1) + "/" + root.questions.length
                    + (root.queuedCount > 0 ? "  ·  +" + root.queuedCount + " queued" : "")
                    : "needs you"
                font.family: Theme.fontMono
                font.pixelSize: 9
                color: Theme.textDim
            }
        }

        Text {
            width: parent.width
            text: root.isInput && root.question ? root.question.question
                : typeof root.request.detail === "string" && root.request.detail !== ""
                    ? root.request.detail : "Approval requested"
            wrapMode: root.isInput ? Text.WordWrap : Text.WrapAnywhere
            maximumLineCount: root.isInput ? 5 : 6
            elide: Text.ElideRight
            font.family: root.isInput ? Theme.fontSans : Theme.fontMono
            font.pixelSize: 10
            color: Theme.textMid
        }

        Column {
            visible: root.isInput && root.question !== null
            width: parent.width
            spacing: 4

            Repeater {
                model: root.question ? root.question.options : []

                delegate: Rectangle {
                    id: option
                    required property var modelData

                    readonly property bool chosen: root.question
                        && T3Code.inputCustomAnswer(root.threadId,
                            root.request.requestId, root.question.id).trim() === ""
                        && T3Code.inputSelectedLabels(root.threadId,
                            root.request.requestId, root.question.id)
                            .indexOf(modelData.label) >= 0

                    width: parent.width
                    height: optionText.implicitHeight + 10
                    radius: 6
                    color: chosen ? Theme.accentBg
                        : optionMouse.containsMouse ? Theme.hoverFillStrong
                        : Qt.rgba(0, 0, 0, 0.17)
                    opacity: root.actionable ? 1 : 0.5
                    activeFocusOnTab: root.actionable

                    Keys.onPressed: event => {
                        if (!root.actionable)
                            return;
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                || event.key === Qt.Key_Space) {
                            T3Code.toggleInputOption(root.threadId, root.request.requestId,
                                root.question.id, option.modelData.label,
                                root.question.multiSelect);
                            event.accepted = true;
                        }
                    }

                    Text {
                        id: marker
                        x: 7
                        anchors.verticalCenter: parent.verticalCenter
                        text: option.chosen ? "●" : "○"
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        color: option.chosen ? Theme.accent : Theme.textDim
                    }

                    Column {
                        id: optionText
                        x: 23
                        y: 5
                        width: parent.width - 30
                        spacing: 1

                        Text {
                            width: parent.width
                            text: option.modelData.label
                            wrapMode: Text.WordWrap
                            font.family: Theme.fontSans
                            font.pixelSize: 10
                            color: option.chosen ? Theme.textHi : Theme.textMid
                        }

                        Text {
                            visible: text !== ""
                            width: parent.width
                            text: option.modelData.description ?? ""
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            wrapMode: Text.WordWrap
                            font.family: Theme.fontSans
                            font.pixelSize: 9
                            color: Theme.textDim
                        }
                    }

                    MouseArea {
                        id: optionMouse
                        anchors.fill: parent
                        enabled: root.actionable
                        hoverEnabled: true
                        onClicked: T3Code.toggleInputOption(root.threadId,
                            root.request.requestId, root.question.id,
                            option.modelData.label, root.question.multiSelect)
                    }
                }
            }
        }

        Rectangle {
            visible: root.isInput && root.question !== null
            width: parent.width
            height: 28
            radius: 6
            color: Qt.rgba(0, 0, 0, 0.2)
            border.width: 1
            border.color: custom.activeFocus ? Theme.accentBgSoft : Theme.hairlineSoft

            TextInput {
                id: custom
                property bool syncing: false
                property string draftKey: root.question
                    ? root.threadId + "|" + root.request.requestId + "|" + root.question.id : ""

                function syncDraft() {
                    if (!root.question)
                        return;
                    const next = T3Code.inputCustomAnswer(root.threadId,
                        root.request.requestId, root.question.id);
                    if (text === next)
                        return;
                    syncing = true;
                    text = next;
                    cursorPosition = text.length;
                    syncing = false;
                }

                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                enabled: root.actionable
                clip: true
                font.family: Theme.fontSans
                font.pixelSize: 10
                color: Theme.textHi
                onDraftKeyChanged: syncDraft()
                onTextChanged: {
                    if (!syncing && activeFocus && root.question)
                        T3Code.setInputCustomAnswer(root.threadId, root.request.requestId,
                            root.question.id, text);
                }
                Component.onCompleted: syncDraft()

                Text {
                    visible: custom.text === "" && !custom.activeFocus
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Or type a custom answer…"
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    color: Theme.textFaint
                }

                Connections {
                    target: T3Code
                    function onUserInputDraftsChanged() { custom.syncDraft(); }
                }
            }
        }

        Row {
            visible: root.isInput
            spacing: 5

            Action {
                label: "Back"
                enabled: root.actionable && root.questionIndex > 0
                onTriggered: T3Code.setInputQuestionIndex(root.threadId,
                    root.request.requestId, root.questionIndex - 1)
            }

            Action {
                visible: root.questionIndex < root.questions.length - 1
                label: "Next"
                enabled: root.actionable && root.answered
                tint: Theme.accentFg
                fill: Theme.accent
                onTriggered: T3Code.setInputQuestionIndex(root.threadId,
                    root.request.requestId, root.questionIndex + 1)
            }

            Action {
                visible: root.questionIndex >= root.questions.length - 1
                label: root.pending ? "Sending…" : "Submit"
                enabled: root.actionable && root.answers !== null
                tint: Theme.accentFg
                fill: Theme.accent
                onTriggered: {
                    const answers = T3Code.buildInputAnswers(root.threadId, root.request);
                    if (answers !== null)
                        T3Code.respondUserInput(root.threadId, root.request.requestId, answers);
                }
            }
        }

        Row {
            visible: !root.isInput
            spacing: 5

            Action {
                label: root.pending ? "Sending…" : "Allow"
                enabled: !root.pending && T3Code.canDispatch
                tint: Theme.accentFg
                fill: Theme.accent
                onTriggered: T3Code.respondApproval(root.threadId,
                    root.request.requestId, "accept")
            }

            Action {
                label: "Session"
                enabled: !root.pending && T3Code.canDispatch
                tint: Theme.accent
                fill: Theme.accentBg
                onTriggered: T3Code.respondApproval(root.threadId,
                    root.request.requestId, "acceptForSession")
            }

            Action {
                label: "Deny"
                enabled: !root.pending && T3Code.canDispatch
                tint: Theme.redText
                fill: Theme.redBg
                onTriggered: T3Code.respondApproval(root.threadId,
                    root.request.requestId, "decline")
            }
        }

        Text {
            visible: root.failure !== ""
            width: parent.width
            text: root.failure
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font.family: Theme.fontSans
            font.pixelSize: 9
            color: Theme.redText
        }
    }
}
