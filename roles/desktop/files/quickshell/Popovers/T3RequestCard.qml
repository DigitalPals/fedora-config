pragma ComponentBehavior: Bound
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

    // Tighter pill, and a brighter default tint than the other pages.
    component Action: ActionButton {
        hPadding: 16
        tint: Theme.textMid
    }

    Column {
        id: content
        x: 7
        y: 7
        width: parent.width - 14
        spacing: 7

        Item {
            width: parent.width
            height: Math.max(requestHeading.implicitHeight, requestStatus.implicitHeight)

            Text {
                id: requestHeading
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.isInput && root.question
                    ? root.question.header.toUpperCase()
                    : root.request.kind === "file-change" ? "EDIT APPROVAL"
                    : root.request.kind === "file-read" ? "READ APPROVAL" : "COMMAND APPROVAL"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                font.weight: Theme.weightSemibold
                font.letterSpacing: 0.7
                color: Theme.amber
            }

            Text {
                id: requestStatus
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.isInput ? (root.questionIndex + 1) + "/" + root.questions.length
                    + (root.queuedCount > 0 ? "  ·  +" + root.queuedCount + " queued" : "")
                    : "needs you"
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontCaption
                color: Theme.textDim
            }
        }

        Text {
            width: parent.width
            text: root.isInput && root.question ? root.question.question
                : typeof root.request.detail === "string" && root.request.detail !== ""
                    ? root.request.detail : "Approval requested"
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            lineHeight: Theme.proseLineHeight
            maximumLineCount: root.isInput ? 5 : 6
            elide: Text.ElideRight
            font.family: root.isInput ? Theme.fontMenu : Theme.fontMono
            font.pixelSize: Theme.fontBody
            color: Theme.textMid
        }

        Text {
            visible: root.isInput && root.question !== null
                && root.question.multiSelect === true
            width: parent.width
            text: "Select one or more options."
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: Theme.textDim
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
                    Accessible.role: root.question && root.question.multiSelect
                        ? Accessible.CheckBox : Accessible.RadioButton
                    Accessible.name: option.modelData.label
                    Accessible.checked: option.chosen

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
                        // Checkbox marks for multi-select, radio marks for
                        // pick-one — mirrors the reference client's controls.
                        text: root.question && root.question.multiSelect
                            ? (option.chosen ? "■" : "□")
                            : (option.chosen ? "●" : "○")
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontCaption
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
                            lineHeight: Theme.proseLineHeight
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontSecondary
                            color: option.chosen ? Theme.textHi : Theme.textMid
                        }

                        Text {
                            visible: text !== ""
                            width: parent.width
                            text: option.modelData.description ?? ""
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            wrapMode: Text.WordWrap
                            lineHeight: Theme.proseLineHeight
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontCaption
                            color: Theme.textDim
                        }
                    }

                    MouseArea {
                        id: optionMouse
                        anchors.fill: parent
                        enabled: root.actionable
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
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
            height: Theme.controlHeight
            radius: 6
            color: Qt.rgba(0, 0, 0, 0.2)
            border.width: 1
            border.color: custom.activeFocus ? Theme.accentBgSoft : Theme.hairlineSoft

            TextInput {
                id: custom
                property bool syncing: false
                // Not dead: onDraftKeyChanged below re-syncs the field when
                // the card moves to another thread, request or question.
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
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontSecondary
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
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontSecondary
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

        // The reference client's four decisions, in its order and wording:
        // quietest on the left, the primary approval on the right. Flow lets
        // the long "Always allow" pill wrap in this narrow card.
        Flow {
            visible: !root.isInput
            width: parent.width
            spacing: 5

            Action {
                label: "Cancel turn"
                enabled: !root.pending && T3Code.canDispatch
                onTriggered: T3Code.respondApproval(root.threadId,
                    root.request.requestId, "cancel")
            }

            Action {
                label: "Decline"
                enabled: !root.pending && T3Code.canDispatch
                tint: Theme.redText
                fill: Theme.redBg
                onTriggered: T3Code.respondApproval(root.threadId,
                    root.request.requestId, "decline")
            }

            Action {
                label: "Always allow this session"
                enabled: !root.pending && T3Code.canDispatch
                tint: Theme.accent
                fill: Theme.accentBg
                onTriggered: T3Code.respondApproval(root.threadId,
                    root.request.requestId, "acceptForSession")
            }

            Action {
                label: root.pending ? "Sending…" : "Approve once"
                enabled: !root.pending && T3Code.canDispatch
                tint: Theme.accentFg
                fill: Theme.accent
                onTriggered: T3Code.respondApproval(root.threadId,
                    root.request.requestId, "accept")
            }
        }

        Text {
            visible: root.failure !== ""
            width: parent.width
            text: root.failure
            wrapMode: Text.WordWrap
            lineHeight: Theme.proseLineHeight
            maximumLineCount: 3
            elide: Text.ElideRight
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: Theme.redText
        }
    }
}
