pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

// Blocking Hermes interaction: approvals, clarification, sudo and secret
// prompts share one compact, non-persistent drawer. Sensitive values never
// leave this component except in the explicit response RPC.
Rectangle {
    id: root

    required property string conversationId
    required property var request
    property string typedValue: ""
    property var selectedValue: null
    property var selectedValues: []
    property var answerDrafts: ({})
    property int questionIndex: 0

    readonly property string requestKey: conversationId + "|" + request.id
    readonly property bool pending: Hermes.actionPending(request.kind,
        conversationId, request.id)
    readonly property string failure: Hermes.actionError(request.kind,
        conversationId, request.id)
    readonly property bool needsValue: request.kind === "clarify"
        || request.kind === "sudo" || request.kind === "secret"
    readonly property bool hasAnswer: !needsValue || typedValue.trim() !== ""
        || selectedValue !== null || selectedValues.length > 0
    readonly property var questions: request.kind === "clarify"
        && Array.isArray(request.questions) ? request.questions : []
    readonly property var question: questions.length > 0
        ? questions[Math.min(questionIndex, questions.length - 1)] : null
    readonly property var currentOptions: question !== null
        ? question.options : request.options
    readonly property bool multiSelect: question !== null
        ? question.multiSelect === true : request.multiSelect === true
    readonly property string currentPrompt: question !== null
        ? question.prompt : (request.prompt || request.detail)
    readonly property var approvalChoices: {
        if (request.kind !== "approval")
            return [];
        const source = Array.isArray(request.options) && request.options.length > 0
            ? request.options : [
                { value: "deny", label: "Deny", description: "" },
                { value: "allow_once", label: "Allow once", description: "" }
            ];
        return source.map(choice => {
            const raw = String(choice.value ?? choice.id ?? choice.label ?? "")
                .toLowerCase().replace(/[ -]+/g, "_");
            let value = raw;
            if (["allow", "approve", "yes", "once"].indexOf(raw) >= 0)
                value = "allow_once";
            else if (["session", "allow_for_session"].indexOf(raw) >= 0)
                value = "allow_session";
            else if (["always", "permanent"].indexOf(raw) >= 0)
                value = "allow_always";
            else if (["reject", "no"].indexOf(raw) >= 0)
                value = "deny";
            if (["deny", "allow_once", "allow_session", "allow_always"]
                    .indexOf(value) < 0)
                return null;
            const label = value === "deny" ? "Deny"
                : value === "allow_once" ? "Allow once"
                    : value === "allow_session" ? "This session" : "Always allow";
            return { value: value, label: label };
        }).filter(choice => choice !== null);
    }

    width: parent ? parent.width : 0
    height: content.implicitHeight + 16
    radius: HermesTheme.panelRadius
    color: HermesTheme.surfaceRaised
    border.width: 1
    border.color: HermesTheme.amberBorder

    onRequestKeyChanged: {
        typedValue = "";
        selectedValue = null;
        selectedValues = [];
        answerDrafts = ({});
        questionIndex = 0;
    }

    function allow(decision) {
        Hermes.respondRequest(conversationId, request, {
            decision: decision,
            choice: decision
        });
    }

    function cancelRequest() {
        Hermes.respondRequest(conversationId, request, {
            decision: "deny",
            choice: "deny",
            cancelled: true
        });
    }

    function submitValue() {
        const value = typedValue.trim() !== "" ? typedValue
            : multiSelect ? selectedValues : selectedValue;
        if (request.kind === "clarify") {
            const wireValue = Array.isArray(value) ? JSON.stringify(value) : value;
            if (questions.length === 0) {
                Hermes.respondRequest(conversationId, request,
                    { answer: wireValue });
                return;
            }
            saveCurrent(value);
            if (questionIndex < questions.length - 1) {
                questionIndex++;
                restoreCurrent();
                return;
            }
            const answers = questions.map(question => ({
                questionId: question.id,
                answer: Array.isArray(answerDrafts[question.id])
                    ? JSON.stringify(answerDrafts[question.id])
                    : answerDrafts[question.id]
            }));
            Hermes.respondClarifyBatch(conversationId, request, answers);
        }
        else if (request.kind === "sudo")
            Hermes.respondRequest(conversationId, request, { decision: "allow", password: value });
        else if (request.kind === "secret")
            Hermes.respondRequest(conversationId, request, { decision: "provide", value: value,
                secret: value });
    }

    function saveCurrent(value) {
        if (!question)
            return;
        const next = Object.assign({}, answerDrafts);
        next[question.id] = value;
        answerDrafts = next;
    }

    function restoreCurrent() {
        const saved = question ? answerDrafts[question.id] : undefined;
        typedValue = typeof saved === "string" && !currentOptions.some(option =>
            option.value === saved) ? saved : "";
        if (multiSelect) {
            selectedValues = Array.isArray(saved) ? saved : [];
            selectedValue = null;
        } else {
            selectedValues = [];
            selectedValue = currentOptions.some(option => option.value === saved)
                ? saved : null;
        }
    }

    function backQuestion() {
        if (questionIndex <= 0)
            return;
        const value = typedValue.trim() !== "" ? typedValue
            : multiSelect ? selectedValues : selectedValue;
        if (value !== null)
            saveCurrent(value);
        questionIndex--;
        restoreCurrent();
    }

    function chooseOption(value) {
        typedValue = "";
        if (!multiSelect) {
            selectedValue = value;
            selectedValues = [];
            return;
        }
        const next = selectedValues.slice();
        const at = next.indexOf(value);
        if (at >= 0)
            next.splice(at, 1);
        else
            next.push(value);
        selectedValues = next;
        selectedValue = null;
    }

    component Action: ActionButton {
        hPadding: 16
        fontFamily: HermesTheme.fontUi
        focusColor: HermesTheme.focus
        buttonRadius: HermesTheme.controlRadius
        tint: HermesTheme.textMuted
        fill: HermesTheme.hover
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 2
        radius: 1
        color: HermesTheme.amber
    }

    Column {
        id: content
        x: 8
        y: 8
        width: parent.width - 16
        spacing: 7

        Item {
            width: parent.width
            height: 20

            Sym {
                id: requestIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                name: root.request.kind === "clarify" ? "help"
                    : root.request.kind === "sudo" ? "admin_panel_settings"
                        : root.request.kind === "secret" ? "key" : "approval"
                size: Theme.iconSmall
                symWeight: 500
                color: HermesTheme.amber
            }

            Text {
                anchors.left: requestIcon.right
                anchors.leftMargin: 7
                anchors.right: waitingLabel.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.request.title
                elide: Text.ElideRight
                font.family: HermesTheme.fontUi
                font.pixelSize: Theme.fontCaption
                font.weight: Theme.weightSemibold
                color: HermesTheme.amber
            }

            Text {
                id: waitingLabel
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.pending ? "sending…"
                    : root.questions.length > 1 ? (root.questionIndex + 1) + "/"
                        + root.questions.length : "needs you"
                font.family: HermesTheme.fontUi
                font.pixelSize: Theme.fontMicro
                color: HermesTheme.textFaint
            }
        }

        Text {
            visible: text !== ""
            width: parent.width
            text: root.currentPrompt
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: 7
            elide: Text.ElideRight
            lineHeight: Theme.proseLineHeight
            font.family: root.request.kind === "approval"
                ? HermesTheme.fontMono : HermesTheme.fontUi
            font.pixelSize: Theme.fontBody
            color: HermesTheme.textSecondary
        }

        Column {
            visible: root.request.kind === "clarify" && root.currentOptions.length > 0
            width: parent.width
            spacing: 4

            Repeater {
                model: root.currentOptions

                delegate: Rectangle {
                    id: option
                    required property var modelData
                    required property int index
                    readonly property bool selected: root.multiSelect
                        ? root.selectedValues.indexOf(modelData.value) >= 0
                        : root.selectedValue === modelData.value

                    width: parent.width
                    height: optionColumn.implicitHeight + 10
                    radius: HermesTheme.controlRadius
                    color: selected ? Theme.chipHover
                        : optionMouse.containsMouse ? HermesTheme.hoverStrong : "transparent"
                    border.width: activeFocus ? 1 : 0
                    border.color: HermesTheme.focus
                    activeFocusOnTab: !root.pending
                    opacity: root.pending ? 0.5 : 1
                    Accessible.role: root.multiSelect
                        ? Accessible.CheckBox : Accessible.RadioButton
                    Accessible.name: modelData.label
                    Accessible.checked: selected

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                || event.key === Qt.Key_Space) {
                            root.chooseOption(option.modelData.value);
                            event.accepted = true;
                        }
                    }

                    Sym {
                        id: radio
                        x: 7
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.multiSelect
                            ? (option.selected ? "check_box" : "check_box_outline_blank")
                            : option.selected ? "radio_button_checked"
                                : "radio_button_unchecked"
                        size: Theme.iconSmall
                        symWeight: 500
                        color: option.selected ? HermesTheme.accent : HermesTheme.textFaint
                    }

                    Column {
                        id: optionColumn
                        x: 29
                        y: 5
                        width: parent.width - 36
                        spacing: 1

                        Text {
                            width: parent.width
                            text: option.modelData.label
                            wrapMode: Text.WordWrap
                            font.family: HermesTheme.fontUi
                            font.pixelSize: Theme.fontSecondary
                            color: HermesTheme.textPrimary
                        }

                        Text {
                            visible: text !== ""
                            width: parent.width
                            text: option.modelData.description
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.family: HermesTheme.fontUi
                            font.pixelSize: Theme.fontCaption
                            color: HermesTheme.textFaint
                        }
                    }

                    MouseArea {
                        id: optionMouse
                        anchors.fill: parent
                        enabled: !root.pending
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.chooseOption(option.modelData.value);
                        }
                    }
                }
            }
        }

        Rectangle {
            visible: root.needsValue
            width: parent.width
            height: Theme.controlHeight
            radius: HermesTheme.controlRadius
            color: HermesTheme.surface
            border.width: 1
            border.color: valueInput.activeFocus ? HermesTheme.focus : HermesTheme.border

            TextInput {
                id: valueInput
                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                enabled: !root.pending
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                echoMode: root.request.kind === "sudo" || root.request.kind === "secret"
                    ? TextInput.Password : TextInput.Normal
                text: root.typedValue
                font.family: HermesTheme.fontUi
                font.pixelSize: Theme.fontSecondary
                color: HermesTheme.textPrimary
                selectionColor: HermesTheme.accentSoft
                onTextEdited: {
                    root.typedValue = text;
                    if (text !== "") {
                        root.selectedValue = null;
                        root.selectedValues = [];
                    }
                }
                Keys.onReturnPressed: {
                    if (!root.pending && root.hasAnswer)
                        root.submitValue();
                }

                Text {
                    visible: valueInput.text === "" && !valueInput.activeFocus
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.request.kind === "sudo" ? "Administrator password…"
                        : root.request.kind === "secret" ? "Secret value…"
                            : "Type an answer…"
                    font.family: HermesTheme.fontUi
                    font.pixelSize: Theme.fontSecondary
                    color: HermesTheme.textFaint
                }
            }
        }

        Flow {
            width: parent.width
            spacing: 5

            Repeater {
                model: root.approvalChoices
                delegate: Action {
                    required property var modelData
                    visible: root.request.kind === "approval"
                    label: modelData.label
                    enabled: !root.pending
                    tint: modelData.value === "deny" ? HermesTheme.red
                        : modelData.value === "allow_once"
                            ? HermesTheme.accentForeground : HermesTheme.textMuted
                    fill: modelData.value === "allow_once"
                        ? HermesTheme.accent : HermesTheme.hover
                    onTriggered: root.allow(modelData.value)
                }
            }

            Action {
                visible: root.request.kind === "clarify" && root.questionIndex > 0
                label: "Back"
                enabled: !root.pending
                onTriggered: root.backQuestion()
            }

            Action {
                visible: root.request.kind !== "approval"
                label: "Cancel"
                enabled: !root.pending
                tint: HermesTheme.red
                onTriggered: root.cancelRequest()
            }

            Action {
                visible: root.request.kind !== "approval"
                label: root.pending ? "Sending…"
                    : root.request.kind === "clarify"
                        && root.questionIndex < root.questions.length - 1
                            ? "Next" : "Submit"
                enabled: !root.pending && root.hasAnswer
                tint: HermesTheme.accentForeground
                fill: HermesTheme.accent
                onTriggered: root.submitValue()
            }
        }

        Text {
            visible: root.failure !== ""
            width: parent.width
            text: root.failure
            wrapMode: Text.WordWrap
            font.family: HermesTheme.fontUi
            font.pixelSize: Theme.fontCaption
            color: HermesTheme.red
        }
    }
}
