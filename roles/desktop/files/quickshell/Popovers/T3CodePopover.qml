import QtQuick
import Quickshell
import "../Common"

// Compact T3 Code action inbox. The fixed header/footer frame a bounded
// scrolling body, and every row expands the same one-thread inspector in
// place. Opening the web client remains an explicit link rather than the row
// click action.
Surface {
    id: root

    spacing: 6

    readonly property int screenHeight: Screens.focused ? Screens.focused.height : 800
    readonly property int maxBodyHeight: Math.max(220, screenHeight - 150)

    readonly property var needsYou: T3Code.threads.filter(thread =>
        thread.cls === "attention" || thread.cls === "error")
    readonly property var readyPlans: T3Code.threads.filter(thread =>
        thread.planReady && thread.cls !== "attention" && thread.cls !== "error")
    readonly property var runningThreads: T3Code.threads.filter(thread =>
        thread.cls === "running" && !thread.planReady)
    readonly property var quietThreads: T3Code.threads.filter(thread =>
        (thread.cls === "done" || thread.cls === "idle") && !thread.planReady)
    readonly property var reviewableDone: quietThreads.filter(thread => thread.cls === "done")
    readonly property int quietDone: reviewableDone.length
    readonly property int quietIdle: quietThreads.length - quietDone

    readonly property bool bulkReviewPending: reviewableDone.some(thread =>
        T3Code.actionPending("settle", thread.id, ""))
    readonly property string bulkReviewError: {
        for (const thread of reviewableDone) {
            const error = T3Code.actionError("settle", thread.id, "");
            if (error !== "")
                return error;
        }
        return "";
    }

    property string chosenId: ""
    property bool manuallyCollapsed: false
    property bool quietExpanded: false

    function preferredThread() {
        if (needsYou.length > 0)
            return needsYou[0];
        if (readyPlans.length > 0)
            return readyPlans[0];
        return null;
    }

    function syncDetail() {
        if (chosenId === "") {
            if (T3Code.detailThreadId !== "")
                T3Code.closeDetail();
            return;
        }
        if (T3Code.state === "connected" && T3Code.detailThreadId !== chosenId)
            T3Code.openDetail(chosenId);
    }

    function ensureSelection() {
        if (T3Code.state !== "connected" || !T3Code.shellReady)
            return;
        if (chosenId !== "") {
            if (T3Code.threads.some(thread => thread.id === chosenId)) {
                syncDetail();
                return;
            }
            // The selected thread settled, snoozed, or was removed. This is
            // not a manual collapse, so advance to the next priority row.
            chosenId = "";
            manuallyCollapsed = false;
        }
        const preferred = preferredThread();
        if (!manuallyCollapsed && preferred)
            chosenId = preferred.id;
        else
            syncDetail();
    }

    function toggleThread(threadId) {
        if (chosenId === threadId) {
            manuallyCollapsed = true;
            chosenId = "";
        } else {
            manuallyCollapsed = false;
            chosenId = threadId;
        }
    }

    function openThread(threadId) {
        Quickshell.execDetached(["xdg-open", T3Code.threadUrl(threadId)]);
        Popouts.close();
    }

    function settleDone() {
        for (const thread of reviewableDone) {
            if (!T3Code.actionPending("settle", thread.id, ""))
                T3Code.settle(thread.id);
        }
    }

    function basename(path) {
        if (typeof path !== "string")
            return "";
        const parts = path.split("/");
        return parts.length > 0 ? parts[parts.length - 1] : path;
    }

    onChosenIdChanged: syncDetail()

    Connections {
        target: T3Code

        function onThreadsChanged() { root.ensureSelection(); }
        function onStateChanged() { root.ensureSelection(); }
        function onShellReadyChanged() { root.ensureSelection(); }
    }

    Component.onCompleted: ensureSelection()
    Component.onDestruction: T3Code.closeDetail()

    // ---- shared controls -------------------------------------------------

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
        color: pillMouse.containsMouse && pill.enabled ? Qt.lighter(fill, 1.3) : fill
        opacity: enabled ? 1 : 0.48
        activeFocusOnTab: enabled && visible
        border.width: activeFocus ? 1 : 0
        border.color: Theme.accent

        Keys.onPressed: event => {
            if (pill.enabled && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space)) {
                pill.activated();
                event.accepted = true;
            }
        }

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
            enabled: pill.enabled
            hoverEnabled: true
            onClicked: pill.activated()
        }
    }

    component OpenLink: Text {
        id: link

        required property string threadId

        text: "open ↗"
        font.family: Theme.fontSans
        font.pixelSize: 10
        font.underline: activeFocus
        color: openLinkMouse.containsMouse ? "#c8e2f4" : Theme.accent
        activeFocusOnTab: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                root.openThread(link.threadId);
                event.accepted = true;
            }
        }

        MouseArea {
            id: openLinkMouse
            anchors.fill: parent
            anchors.margins: -3
            hoverEnabled: true
            onClicked: root.openThread(link.threadId)
        }
    }

    component GroupLabel: Text {
        leftPadding: 6
        topPadding: 3
        bottomPadding: 1
        font.family: Theme.fontSans
        font.pixelSize: 10
        font.weight: 600
        font.letterSpacing: 0.6
        color: Theme.textDim
    }

    component InlineError: Text {
        width: parent ? parent.width : implicitWidth
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
        font.family: Theme.fontSans
        font.pixelSize: 10
        color: Theme.redText
    }

    // ---- structured input -----------------------------------------------

    component StructuredInput: Column {
        id: inputCard

        required property string threadId
        required property var prompt

        readonly property var questions: Array.isArray(prompt.questions) ? prompt.questions : []
        readonly property int storedIndex: T3Code.inputQuestionIndex(threadId, prompt.requestId)
        readonly property int questionIndex: questions.length > 0
            ? Math.max(0, Math.min(storedIndex, questions.length - 1)) : 0
        readonly property var question: questions.length > 0 ? questions[questionIndex] : null
        readonly property bool sending: T3Code.actionPending("input", threadId, prompt.requestId)
        readonly property string failure: T3Code.actionError("input", threadId, prompt.requestId)
        readonly property bool answered: question !== null
            && T3Code.inputQuestionAnswered(threadId, prompt.requestId, question)
        readonly property var answers: T3Code.buildInputAnswers(threadId, prompt)
        readonly property bool complete: answers !== null
        readonly property bool lastQuestion: questionIndex >= questions.length - 1

        width: parent.width
        spacing: 7

        Item {
            width: parent.width
            height: 17

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: inputCard.question ? inputCard.question.header.toUpperCase() : "QUESTION"
                font.family: Theme.fontSans
                font.pixelSize: 10
                font.weight: 600
                font.letterSpacing: 0.5
                color: Theme.amber
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: (inputCard.questionIndex + 1) + "/" + inputCard.questions.length
                font.family: Theme.fontMono
                font.pixelSize: 10
                color: Theme.textDim
            }
        }

        Text {
            visible: inputCard.question !== null
            width: parent.width
            text: inputCard.question ? inputCard.question.question : ""
            wrapMode: Text.WordWrap
            font.family: Theme.fontSans
            font.pixelSize: 11
            color: Theme.textHi
        }

        Text {
            visible: inputCard.question !== null && inputCard.question.multiSelect === true
            width: parent.width
            text: "Select one or more."
            font.family: Theme.fontSans
            font.pixelSize: 10
            color: Theme.textDim
        }

        Column {
            visible: inputCard.question !== null
            width: parent.width
            spacing: 4

            Repeater {
                model: inputCard.question ? inputCard.question.options : []

                delegate: Rectangle {
                    id: optionRow

                    required property var modelData

                    readonly property bool selected: inputCard.question
                        && T3Code.inputCustomAnswer(inputCard.threadId,
                            inputCard.prompt.requestId, inputCard.question.id).trim() === ""
                        && T3Code.inputSelectedLabels(inputCard.threadId,
                            inputCard.prompt.requestId, inputCard.question.id)
                            .indexOf(modelData.label) >= 0

                    width: parent.width
                    height: optionText.implicitHeight + 12
                    radius: 6
                    color: selected ? Theme.accentBg : optionMouse.containsMouse
                        ? Theme.hoverFillStrong : Qt.rgba(0, 0, 0, 0.18)
                    border.width: 1
                    border.color: activeFocus ? Theme.accent
                        : selected ? Qt.rgba(158 / 255, 203 / 255, 235 / 255, 0.32)
                        : Theme.hairlineSoft
                    opacity: inputCard.sending ? 0.55 : 1
                    activeFocusOnTab: !inputCard.sending

                    Keys.onPressed: event => {
                        if (!inputCard.sending && (event.key === Qt.Key_Return
                                || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
                            T3Code.toggleInputOption(inputCard.threadId,
                                inputCard.prompt.requestId, inputCard.question.id,
                                optionRow.modelData.label, inputCard.question.multiSelect);
                            event.accepted = true;
                        }
                    }

                    Text {
                        id: optionMark
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: optionRow.selected
                            ? (inputCard.question.multiSelect ? "✓" : "●")
                            : (inputCard.question.multiSelect ? "□" : "○")
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                        color: optionRow.selected ? Theme.accent : Theme.textDim
                    }

                    Column {
                        id: optionText
                        x: 27
                        y: 6
                        width: parent.width - 35
                        spacing: 1

                        Text {
                            width: parent.width
                            text: optionRow.modelData.label
                            wrapMode: Text.WordWrap
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: 500
                            color: optionRow.selected ? Theme.textHi : Theme.textMid
                        }

                        Text {
                            visible: text !== "" && text !== optionRow.modelData.label
                            width: parent.width
                            text: typeof optionRow.modelData.description === "string"
                                ? optionRow.modelData.description : ""
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.family: Theme.fontSans
                            font.pixelSize: 10
                            color: Theme.textDim
                        }
                    }

                    MouseArea {
                        id: optionMouse
                        anchors.fill: parent
                        enabled: !inputCard.sending
                        hoverEnabled: true
                        onClicked: T3Code.toggleInputOption(inputCard.threadId,
                            inputCard.prompt.requestId, inputCard.question.id,
                            optionRow.modelData.label, inputCard.question.multiSelect)
                    }
                }
            }
        }

        Rectangle {
            id: customBox

            visible: inputCard.question !== null
            width: parent.width
            height: 28
            radius: 6
            color: Qt.rgba(0, 0, 0, 0.2)
            border.width: 1
            border.color: customInput.activeFocus ? Theme.accentBgSoft : Theme.hairlineSoft
            opacity: inputCard.sending ? 0.55 : 1

            TextInput {
                id: customInput

                property bool syncing: false
                property string draftKey: inputCard.question
                    ? inputCard.threadId + "|" + inputCard.prompt.requestId
                        + "|" + inputCard.question.id : ""

                function syncDraft() {
                    if (!inputCard.question)
                        return;
                    const next = T3Code.inputCustomAnswer(inputCard.threadId,
                        inputCard.prompt.requestId, inputCard.question.id);
                    if (text === next)
                        return;
                    syncing = true;
                    text = next;
                    cursorPosition = text.length;
                    syncing = false;
                }

                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                verticalAlignment: TextInput.AlignVCenter
                enabled: !inputCard.sending
                clip: true
                font.family: Theme.fontSans
                font.pixelSize: 11
                color: Theme.textHi
                onDraftKeyChanged: syncDraft()
                onTextChanged: {
                    if (!syncing && activeFocus && inputCard.question)
                        T3Code.setInputCustomAnswer(inputCard.threadId,
                            inputCard.prompt.requestId, inputCard.question.id, text);
                }
                Component.onCompleted: syncDraft()

                Text {
                    visible: customInput.text === "" && !customInput.activeFocus
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Or type a custom answer…"
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    color: Theme.textFaint
                }

                Connections {
                    target: T3Code
                    function onUserInputDraftsChanged() { customInput.syncDraft(); }
                }
            }
        }

        Item {
            width: parent.width
            height: 22

            Row {
                anchors.left: parent.left
                spacing: 5

                Pill {
                    label: "Back"
                    enabled: !inputCard.sending && inputCard.questionIndex > 0
                    onActivated: T3Code.setInputQuestionIndex(inputCard.threadId,
                        inputCard.prompt.requestId, inputCard.questionIndex - 1)
                }

                Pill {
                    visible: !inputCard.lastQuestion
                    label: "Next"
                    enabled: !inputCard.sending && inputCard.answered
                    tint: Theme.accentFg
                    fill: Theme.accent
                    weight: 600
                    onActivated: T3Code.setInputQuestionIndex(inputCard.threadId,
                        inputCard.prompt.requestId, inputCard.questionIndex + 1)
                }

                Pill {
                    visible: inputCard.lastQuestion
                    label: inputCard.sending ? "Sending…" : "Submit"
                    enabled: !inputCard.sending && inputCard.complete
                    tint: Theme.accentFg
                    fill: Theme.accent
                    weight: 600
                    onActivated: {
                        const answers = T3Code.buildInputAnswers(inputCard.threadId,
                            inputCard.prompt);
                        if (answers !== null)
                            T3Code.respondUserInput(inputCard.threadId,
                                inputCard.prompt.requestId, answers);
                    }
                }
            }

            Text {
                visible: inputCard.prompt && T3Code.detailPendingInputs.length > 1
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "+" + (T3Code.detailPendingInputs.length - 1) + " queued"
                font.family: Theme.fontSans
                font.pixelSize: 10
                color: Theme.textDim
            }
        }

        InlineError {
            visible: inputCard.failure !== ""
            text: inputCard.failure
        }
    }

    // ---- one selected-thread inspector ----------------------------------

    component Inspector: Column {
        id: inspector

        required property var thread

        readonly property bool detailMatches: T3Code.detailThreadId === thread.id
        readonly property bool activeTurn: thread.cls === "running"
            || thread.sessionStatus === "starting" || thread.sessionStatus === "running"
        readonly property bool hasRequests: thread.pendingApprovals || thread.pendingInput
            || (detailMatches && (T3Code.detailApprovals.length > 0
                || T3Code.detailPendingInputs.length > 0))
        readonly property bool actionablePlan: thread.planReady
            || (detailMatches && T3Code.detailActionablePlan !== null)
        readonly property bool canFollowUp: detailMatches && !T3Code.detailLoading
            && thread.canPrompt && !hasRequests && !actionablePlan
        readonly property bool canReview: detailMatches && !T3Code.detailLoading
            && !activeTurn && !hasRequests

        width: parent.width
        spacing: 0

        Rectangle {
            width: parent.width - 8
            x: 4
            height: inspectorCol.implicitHeight + 16
            radius: 9
            color: Qt.rgba(0, 0, 0, 0.22)
            border.width: 1
            border.color: inspector.thread.cls === "error" ? Theme.redBorder
                : inspector.actionablePlan ? Qt.rgba(158 / 255, 203 / 255, 235 / 255, 0.28)
                : inspector.hasRequests ? Theme.amberBorder : Theme.hairlineSoft

            Column {
                id: inspectorCol
                x: 9
                y: 8
                width: parent.width - 18
                spacing: 8

                Text {
                    visible: inspector.detailMatches && T3Code.detailLoading
                    width: parent.width
                    text: "Loading thread…"
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    color: Theme.textDim
                }

                InlineError {
                    visible: inspector.detailMatches && T3Code.detailError !== ""
                    text: T3Code.detailError
                }

                Column {
                    visible: inspector.detailMatches && T3Code.detailLatestAssistant !== null
                    width: parent.width
                    spacing: 3

                    Text {
                        text: "LATEST RESPONSE"
                        font.family: Theme.fontSans
                        font.pixelSize: 9
                        font.weight: 600
                        font.letterSpacing: 0.5
                        color: Theme.textDim
                    }

                    Text {
                        width: parent.width
                        text: T3Code.detailLatestAssistant
                            ? T3Code.detailLatestAssistant.text : ""
                        wrapMode: Text.WordWrap
                        maximumLineCount: 5
                        elide: Text.ElideRight
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        color: Theme.textMid
                    }
                }

                Column {
                    visible: inspector.detailMatches && T3Code.detailLatestActivity !== null
                    width: parent.width
                    spacing: 3

                    Text {
                        text: T3Code.detailLatestActivity
                            && T3Code.detailLatestActivity.tone === "error"
                            ? "LATEST ERROR" : "LATEST ACTIVITY"
                        font.family: Theme.fontSans
                        font.pixelSize: 9
                        font.weight: 600
                        font.letterSpacing: 0.5
                        color: T3Code.detailLatestActivity
                            && T3Code.detailLatestActivity.tone === "error"
                            ? Theme.redText : Theme.textDim
                    }

                    Text {
                        width: parent.width
                        text: T3Code.detailLatestActivity
                            ? T3Code.detailLatestActivity.summary : ""
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        color: T3Code.detailLatestActivity
                            && T3Code.detailLatestActivity.tone === "error"
                            ? Theme.redText : Theme.textLow
                    }
                }

                Column {
                    visible: inspector.detailMatches && T3Code.detailCheckpointSummary !== null
                    width: parent.width
                    spacing: 2

                    Text {
                        text: "READY CHECKPOINT"
                        font.family: Theme.fontSans
                        font.pixelSize: 9
                        font.weight: 600
                        font.letterSpacing: 0.5
                        color: Theme.textDim
                    }

                    Text {
                        width: parent.width
                        text: {
                            const checkpoint = T3Code.detailCheckpointSummary;
                            if (!checkpoint)
                                return "";
                            return checkpoint.fileCount + (checkpoint.fileCount === 1 ? " file" : " files")
                                + " · +" + checkpoint.additions + " −" + checkpoint.deletions;
                        }
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                        color: Theme.textMid
                    }

                    Text {
                        visible: text !== ""
                        width: parent.width
                        text: {
                            const checkpoint = T3Code.detailCheckpointSummary;
                            if (!checkpoint || !Array.isArray(checkpoint.filenames))
                                return "";
                            return checkpoint.filenames.map(path => root.basename(path)).join(" · ");
                        }
                        elide: Text.ElideMiddle
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        color: Theme.textDim
                    }
                }

                Column {
                    visible: inspector.actionablePlan
                    width: parent.width
                    spacing: 3

                    Text {
                        text: "READY TO REVIEW"
                        font.family: Theme.fontSans
                        font.pixelSize: 9
                        font.weight: 600
                        font.letterSpacing: 0.5
                        color: Theme.accent
                    }

                    Text {
                        width: parent.width
                        text: T3Code.detailActionablePlan
                            && typeof T3Code.detailActionablePlan.planMarkdown === "string"
                            ? T3Code.detailActionablePlan.planMarkdown
                            : "Plan details are available in T3 Code."
                        wrapMode: Text.WordWrap
                        maximumLineCount: 5
                        elide: Text.ElideRight
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        color: Theme.textMid
                    }
                }

                Rectangle {
                    visible: inspector.detailMatches && T3Code.detailPendingInputs.length > 0
                    width: parent.width
                    height: inputPanel.implicitHeight + 14
                    radius: 7
                    color: Theme.amberBgSoft
                    border.width: 1
                    border.color: Theme.amberBorder

                    StructuredInput {
                        id: inputPanel
                        x: 7
                        y: 7
                        width: parent.width - 14
                        threadId: inspector.thread.id
                        prompt: T3Code.detailPendingInputs.length > 0
                            ? T3Code.detailPendingInputs[0] : ({ requestId: "", questions: [] })
                    }
                }

                Text {
                    visible: inspector.detailMatches && !T3Code.detailLoading
                        && inspector.thread.pendingInput && T3Code.detailPendingInputs.length === 0
                    width: parent.width
                    text: "This question needs the full T3 Code client."
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    color: Theme.amber
                }

                Repeater {
                    model: inspector.detailMatches ? T3Code.detailApprovals : []

                    delegate: Column {
                        id: approval

                        required property var modelData

                        readonly property bool sending: T3Code.actionPending("approval",
                            inspector.thread.id, modelData.requestId)
                        readonly property string failure: T3Code.actionError("approval",
                            inspector.thread.id, modelData.requestId)

                        width: parent.width
                        spacing: 6

                        Rectangle {
                            width: parent.width
                            height: approvalText.implicitHeight + 12
                            radius: 6
                            color: Theme.amberBgSoft
                            border.width: 1
                            border.color: Theme.amberBorder

                            Row {
                                id: approvalText
                                x: 7
                                y: 6
                                width: parent.width - 14
                                spacing: 6

                                Text {
                                    id: approvalKind
                                    text: approval.modelData.kind === "file-change" ? "edit"
                                        : approval.modelData.kind === "file-read" ? "read" : "run"
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                    color: Theme.amber
                                }

                                Text {
                                    width: parent.width - approvalKind.width - 6
                                    text: approval.modelData.detail !== ""
                                        ? approval.modelData.detail : "Approval requested"
                                    wrapMode: Text.WrapAnywhere
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                    color: Theme.textMid
                                }
                            }
                        }

                        Row {
                            spacing: 5

                            Pill {
                                label: approval.sending ? "Sending…" : "Allow"
                                enabled: !approval.sending
                                tint: Theme.accentFg
                                fill: Theme.accent
                                weight: 600
                                onActivated: T3Code.respondApproval(inspector.thread.id,
                                    approval.modelData.requestId, "accept")
                            }

                            Pill {
                                label: "Session"
                                enabled: !approval.sending
                                tint: Theme.accent
                                fill: Theme.accentBg
                                onActivated: T3Code.respondApproval(inspector.thread.id,
                                    approval.modelData.requestId, "acceptForSession")
                            }

                            Pill {
                                label: "Deny"
                                enabled: !approval.sending
                                tint: Theme.redText
                                fill: Theme.redBg
                                onActivated: T3Code.respondApproval(inspector.thread.id,
                                    approval.modelData.requestId, "decline")
                            }
                        }

                        InlineError {
                            visible: approval.failure !== ""
                            text: approval.failure
                        }
                    }
                }

                Text {
                    visible: inspector.detailMatches && !T3Code.detailLoading
                        && inspector.thread.pendingApprovals && T3Code.detailApprovals.length === 0
                    width: parent.width
                    text: "This approval needs the full T3 Code client."
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    color: Theme.amber
                }

                Rectangle {
                    id: followBox

                    property bool submitted: false

                    visible: inspector.canFollowUp
                    width: parent.width
                    height: 28
                    radius: Theme.chipRadius
                    color: Theme.hoverFill
                    border.width: 1
                    border.color: followInput.activeFocus ? Theme.accentBgSoft : Theme.hairlineSoft

                    function send() {
                        const message = followInput.text.trim();
                        if (message === "" || T3Code.actionPending("prompt", inspector.thread.id, ""))
                            return;
                        if (T3Code.startTurn(inspector.thread.id, message) !== "")
                            submitted = true;
                    }

                    TextInput {
                        id: followInput
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 34
                        verticalAlignment: TextInput.AlignVCenter
                        enabled: !T3Code.actionPending("prompt", inspector.thread.id, "")
                        clip: true
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        color: Theme.textHi
                        onAccepted: followBox.send()

                        Text {
                            visible: followInput.text === "" && !followInput.activeFocus
                            anchors.verticalCenter: parent.verticalCenter
                            text: T3Code.actionPending("prompt", inspector.thread.id, "")
                                ? "Sending…" : "Send a follow-up…"
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            color: Theme.textFaint
                        }
                    }

                    MouseArea {
                        anchors.right: parent.right
                        width: 32
                        height: parent.height
                        enabled: followInput.text.trim() !== ""
                            && !T3Code.actionPending("prompt", inspector.thread.id, "")
                        hoverEnabled: true
                        onClicked: followBox.send()

                        Text {
                            anchors.centerIn: parent
                            text: T3Code.actionPending("prompt", inspector.thread.id, "") ? "…" : "↑"
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                            font.weight: 700
                            color: followInput.text.trim() !== "" ? Theme.accent : Theme.textFaint
                        }
                    }

                    Connections {
                        target: T3Code
                        function onActionStatesChanged() {
                            if (!followBox.submitted
                                    || T3Code.actionPending("prompt", inspector.thread.id, ""))
                                return;
                            if (T3Code.actionError("prompt", inspector.thread.id, "") === "")
                                followInput.text = "";
                            followBox.submitted = false;
                        }
                    }
                }

                InlineError {
                    visible: inspector.detailMatches
                        && T3Code.actionError("prompt", inspector.thread.id, "") !== ""
                    text: T3Code.actionError("prompt", inspector.thread.id, "")
                }

                Item {
                    visible: inspector.activeTurn || inspector.canReview
                    width: parent.width
                    height: visible ? 22 : 0

                    Row {
                        anchors.left: parent.left
                        spacing: 6

                        Pill {
                            visible: inspector.activeTurn
                            label: T3Code.actionPending("interrupt", inspector.thread.id, "")
                                ? "Stopping…" : "Stop"
                            enabled: !T3Code.actionPending("interrupt", inspector.thread.id, "")
                            tint: Theme.redText
                            fill: Theme.redBg
                            onActivated: T3Code.interrupt(inspector.thread.id)
                        }

                        Pill {
                            visible: inspector.canReview
                            label: T3Code.actionPending("settle", inspector.thread.id, "")
                                ? "Marking…" : "Mark reviewed"
                            enabled: !T3Code.actionPending("settle", inspector.thread.id, "")
                            tint: Theme.accent
                            fill: Theme.accentBg
                            onActivated: T3Code.settle(inspector.thread.id)
                        }
                    }
                }

                InlineError {
                    visible: inspector.detailMatches && text !== ""
                    text: {
                        const stopError = T3Code.actionError("interrupt", inspector.thread.id, "");
                        if (stopError !== "")
                            return stopError;
                        return T3Code.actionError("settle", inspector.thread.id, "");
                    }
                }
            }
        }
    }

    // ---- grouped thread rows --------------------------------------------

    component ThreadEntry: Column {
        id: entry

        required property var thread

        readonly property bool selected: root.chosenId === thread.id
        readonly property bool isError: thread.cls === "error"
        readonly property color statusColor: isError ? Theme.red
            : thread.cls === "attention" ? Theme.amber
            : thread.planReady ? Theme.accent
            : thread.cls === "running" ? Theme.accent
            : thread.cls === "done" ? Theme.textMid : Theme.dotDim

        width: parent.width
        spacing: 4

        Rectangle {
            id: threadRow

            width: parent.width - 4
            x: 2
            height: 42
            radius: 8
            color: entry.selected ? Theme.activeFill
                : rowMouse.containsMouse ? Theme.hoverFill : "transparent"
            border.width: entry.selected || activeFocus ? 1 : 0
            border.color: activeFocus ? Theme.accent
                : entry.isError ? Theme.redBorder
                : entry.thread.cls === "attention" ? Theme.amberBorder : Theme.hairlineSoft
            activeFocusOnTab: true

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                        || event.key === Qt.Key_Space) {
                    root.toggleThread(entry.thread.id);
                    event.accepted = true;
                }
            }

            MouseArea {
                id: rowMouse
                z: 0
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.toggleThread(entry.thread.id)
            }

            Rectangle {
                id: rowDot
                z: 1
                x: 9
                anchors.verticalCenter: parent.verticalCenter
                width: 7
                height: 7
                radius: 4
                color: entry.statusColor

                SequentialAnimation on opacity {
                    running: entry.thread.cls === "running"
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.3; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.3; to: 1; duration: 900; easing.type: Easing.InOutSine }
                }
            }

            Column {
                z: 1
                anchors.left: rowDot.right
                anchors.leftMargin: 9
                anchors.right: rowOpen.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    width: parent.width
                    text: entry.thread.title
                    elide: Text.ElideRight
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight: entry.selected ? 600 : 500
                    color: entry.thread.cls === "idle" ? Theme.textMid : Theme.textHi
                }

                Text {
                    width: parent.width
                    text: {
                        const parts = [];
                        if (entry.thread.project !== "")
                            parts.push(entry.thread.project);
                        if (entry.thread.sessionStatus !== "")
                            parts.push(entry.thread.sessionStatus);
                        if (entry.thread.model !== "" && entry.thread.cls === "running")
                            parts.push(entry.thread.model);
                        const relative = T3Code.relTime(entry.thread.updatedAt);
                        if (relative !== "")
                            parts.push(relative);
                        return parts.join(" · ");
                    }
                    elide: Text.ElideRight
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    color: Theme.textDim
                }
            }

            OpenLink {
                id: rowOpen
                z: 2
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                threadId: entry.thread.id
            }
        }

        Loader {
            width: parent.width
            height: item ? item.implicitHeight : 0
            active: entry.selected
            visible: active

            sourceComponent: Inspector {
                width: parent ? parent.width : 0
                thread: entry.thread
            }
        }
    }

    // ---- fixed header ----------------------------------------------------

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
                        const env = T3Code.environmentLabel !== ""
                            ? T3Code.environmentLabel : "connected";
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

    // ---- bounded scrolling body -----------------------------------------

    Item {
        id: bodyViewport

        width: parent.width
        height: Math.min(root.maxBodyHeight, bodyColumn.implicitHeight)

        Flickable {
            id: bodyFlick

            anchors.fill: parent
            contentWidth: width
            contentHeight: bodyColumn.implicitHeight
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            activeFocusOnTab: true

            Keys.onPressed: event => {
                const step = Math.max(48, bodyFlick.height * 0.8);
                if (event.key === Qt.Key_PageDown || event.key === Qt.Key_Down) {
                    bodyFlick.contentY = Math.min(bodyFlick.contentHeight - bodyFlick.height,
                        bodyFlick.contentY + (event.key === Qt.Key_Down ? 36 : step));
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_Up) {
                    bodyFlick.contentY = Math.max(0,
                        bodyFlick.contentY - (event.key === Qt.Key_Up ? 36 : step));
                    event.accepted = true;
                } else if (event.key === Qt.Key_Home) {
                    bodyFlick.contentY = 0;
                    event.accepted = true;
                } else if (event.key === Qt.Key_End) {
                    bodyFlick.contentY = Math.max(0, bodyFlick.contentHeight - bodyFlick.height);
                    event.accepted = true;
                }
            }

            Column {
                id: bodyColumn
                width: bodyFlick.width - (bodyFlick.contentHeight > bodyFlick.height ? 5 : 0)
                spacing: 6

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
                    text: T3Code.state === "connecting"
                        ? "Connecting…" : "Server unreachable — retrying"
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    color: Theme.textDim
                }

                Text {
                    visible: T3Code.state === "connected" && T3Code.shellReady
                        && T3Code.threads.length === 0
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

                GroupLabel {
                    visible: root.needsYou.length > 0
                    text: "NEEDS YOU"
                    color: Theme.amber
                }

                Column {
                    visible: T3Code.state === "connected" && root.needsYou.length > 0
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: root.needsYou

                        delegate: ThreadEntry {
                            required property var modelData
                            thread: modelData
                        }
                    }
                }

                GroupLabel {
                    visible: root.readyPlans.length > 0
                    text: "READY TO REVIEW"
                    color: Theme.accent
                }

                Column {
                    visible: T3Code.state === "connected" && root.readyPlans.length > 0
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: root.readyPlans

                        delegate: ThreadEntry {
                            required property var modelData
                            thread: modelData
                        }
                    }
                }

                GroupLabel {
                    visible: root.runningThreads.length > 0
                    text: "RUNNING"
                }

                Column {
                    visible: T3Code.state === "connected" && root.runningThreads.length > 0
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: root.runningThreads

                        delegate: ThreadEntry {
                            required property var modelData
                            thread: modelData
                        }
                    }
                }

                Rectangle {
                    id: quietSummary

                    visible: T3Code.state === "connected" && root.quietThreads.length > 0
                    width: parent.width - 4
                    x: 2
                    height: 30
                    radius: 8
                    color: quietMouse.containsMouse ? Theme.hoverFill : Qt.rgba(1, 1, 1, 0.03)

                    MouseArea {
                        id: quietMouse
                        z: 0
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.quietExpanded = !root.quietExpanded
                    }

                    Rectangle {
                        z: 1
                        id: quietDot
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7
                        height: 7
                        radius: 4
                        color: Theme.textMid
                    }

                    Text {
                        z: 1
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
                        z: 2
                        visible: root.quietDone > 0
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.bulkReviewPending ? "marking…" : "mark reviewed"
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        color: reviewMouse.containsMouse ? "#c8e2f4" : Theme.accent
                        opacity: root.bulkReviewPending ? 0.6 : 1

                        MouseArea {
                            id: reviewMouse
                            anchors.fill: parent
                            anchors.margins: -3
                            enabled: !root.bulkReviewPending
                            hoverEnabled: true
                            onClicked: root.settleDone()
                        }
                    }
                }

                InlineError {
                    visible: root.bulkReviewError !== ""
                    x: 6
                    width: parent.width - 12
                    text: root.bulkReviewError
                }

                Column {
                    visible: T3Code.state === "connected" && root.quietExpanded
                        && root.quietThreads.length > 0
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: root.quietThreads

                        delegate: ThreadEntry {
                            required property var modelData
                            thread: modelData
                        }
                    }
                }
            }
        }

        Rectangle {
            visible: bodyFlick.contentHeight > bodyFlick.height + 1
            z: 10
            anchors.right: parent.right
            anchors.rightMargin: 1
            width: 2
            height: Math.max(24, bodyViewport.height * bodyFlick.visibleArea.heightRatio)
            y: bodyFlick.visibleArea.yPosition * bodyViewport.height
            radius: 1
            color: Theme.textFaint
            opacity: bodyFlick.moving ? 0.8 : 0.45
        }
    }

    // ---- fixed footer ----------------------------------------------------

    Item {
        width: parent.width
        height: 27

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: Theme.hairlineSoft
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.right: openClient.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 2
            text: {
                const status = T3Code.state === "connected" ? "connected" : T3Code.state;
                return status + (T3Code.host !== ""
                    ? " · " + T3Code.host.replace(/^https?:\/\//, "") : "");
            }
            elide: Text.ElideRight
            font.family: Theme.fontMono
            font.pixelSize: 10
            color: Theme.textDim
        }

        Text {
            id: openClient
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 2
            text: "Open T3 Code"
            font.family: Theme.fontSans
            font.pixelSize: 11
            font.weight: 500
            color: openMouse.containsMouse ? "#c8e2f4" : Theme.accent

            MouseArea {
                id: openMouse
                anchors.fill: parent
                anchors.margins: -3
                hoverEnabled: true
                onClicked: {
                    Quickshell.execDetached(["xdg-open", T3Code.host !== ""
                        ? T3Code.host : "https://app.t3.codes"]);
                    Popouts.close();
                }
            }
        }
    }
}
