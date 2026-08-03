import QtQuick
import Quickshell
import "../Common"

// Fixed, text-only composer with provider/model/runtime/mode and every model
// trait advertised by server.getConfig. The singleton owns all draft values.
Column {
    id: root

    property string threadId: ""
    property bool newThread: false
    property bool editable: true
    property bool sendEnabled: true
    property string sendLabel: "Send"
    signal sendRequested()

    readonly property var draft: newThread ? T3Code.newThreadDraft : T3Code.threadDraft(threadId)
    readonly property var providers: newThread ? T3Code.newProviderChoices()
        : T3Code.threadProviderChoices(threadId)
    readonly property var models: newThread ? T3Code.newModelChoices()
        : T3Code.threadModelChoices(threadId)
    readonly property var traits: T3Code.draftTraitDescriptors(draft)
    readonly property var selectedProvider: T3Code.providerConfiguration(draft.instanceId)
    readonly property bool showInteraction: draft.modeFixed !== true
        && T3Code.providerShowsInteraction(draft.instanceId)
    readonly property bool overLimit: promptEdit.text.length > T3Code.maxPromptChars
    readonly property string actionKind: newThread ? "new" : "prompt"
    readonly property string actionThreadId: newThread ? "" : threadId
    readonly property bool sending: T3Code.actionPending(actionKind, actionThreadId, "")

    spacing: 5

    function focusPrompt() {
        promptEdit.forceActiveFocus();
        promptEdit.cursorPosition = promptEdit.text.length;
    }

    function persistPrompt(value) {
        if (newThread)
            T3Code.setNewPrompt(value);
        else
            T3Code.setThreadPrompt(threadId, value);
    }

    function chooseProvider(value) {
        if (newThread)
            T3Code.setNewProvider(value);
        else
            T3Code.setThreadProvider(threadId, value);
    }

    function chooseModel(value) {
        if (newThread)
            T3Code.setNewModel(value);
        else
            T3Code.setThreadModel(threadId, value);
    }

    function chooseRuntime(value) {
        if (newThread)
            T3Code.setNewRuntime(value);
        else
            T3Code.setThreadRuntime(threadId, value);
    }

    function chooseInteraction(value) {
        if (newThread)
            T3Code.setNewInteraction(value);
        else
            T3Code.setThreadInteraction(threadId, value);
    }

    function chooseTrait(id, value) {
        if (newThread)
            T3Code.updateNewTrait(id, value);
        else
            T3Code.updateThreadTrait(threadId, id, value);
    }

    function traitLabel(descriptor) {
        const id = String(descriptor?.id ?? "").toLowerCase();
        if (id === "effort" || id === "reasoningeffort" || id === "reasoning")
            return "Reasoning";
        return descriptor?.label ?? "Option";
    }

    function syncPrompt() {
        const next = draft && typeof draft.prompt === "string" ? draft.prompt : "";
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

    Row {
        width: parent.width
        spacing: 5

        T3Picker {
            width: (parent.width - 5) * 0.42
            label: "Provider"
            value: root.draft.instanceId ?? ""
            options: root.providers
            openUpward: !root.newThread
            enabled: root.editable && !root.sending && options.length > 0
            onSelected: value => root.chooseProvider(value)
        }

        T3Picker {
            width: (parent.width - 5) * 0.58
            label: "Model"
            value: root.draft.model ?? ""
            options: root.models
            openUpward: !root.newThread
            menuRows: 8
            enabled: root.editable && !root.sending && options.length > 0
            onSelected: value => root.chooseModel(value)
        }
    }

    Row {
        width: parent.width
        spacing: 5

        T3Picker {
            width: root.showInteraction ? (parent.width - 5) / 2 : parent.width
            label: "Access"
            value: root.draft.runtimeMode ?? "full-access"
            options: [
                { id: "approval-required", label: "Ask first" },
                { id: "auto-accept-edits", label: "Auto edits" },
                { id: "auto", label: "Auto" },
                { id: "full-access", label: "Full access" }
            ]
            openUpward: !root.newThread
            enabled: root.editable && !root.sending
            onSelected: value => root.chooseRuntime(value)
        }

        T3Picker {
            visible: root.showInteraction
            width: (parent.width - 5) / 2
            label: "Mode"
            value: root.draft.interactionMode ?? "default"
            options: [
                { id: "default", label: "Default" },
                { id: "plan", label: "Plan" }
            ]
            openUpward: !root.newThread
            enabled: root.editable && !root.sending
            onSelected: value => root.chooseInteraction(value)
        }
    }

    Repeater {
        model: root.traits

        delegate: Item {
            id: traitRow

            required property var modelData
            width: root.width
            height: modelData.type === "select" ? 30 : 26

            T3Picker {
                visible: traitRow.modelData.type === "select"
                anchors.fill: parent
                label: root.traitLabel(traitRow.modelData)
                value: traitRow.modelData.currentValue ?? ""
                options: traitRow.modelData.options ?? []
                enabled: root.editable && !root.sending
                onSelected: value => root.chooseTrait(traitRow.modelData.id, value)
            }

            Rectangle {
                visible: traitRow.modelData.type === "boolean"
                anchors.fill: parent
                radius: 6
                color: traitMouse.containsMouse && root.editable
                    ? Theme.hoverFillStrong : Theme.hoverFill
                opacity: root.editable && !root.sending ? 1 : 0.48
                activeFocusOnTab: root.editable && !root.sending

                Keys.onPressed: event => {
                    if (!root.editable || root.sending)
                        return;
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                            || event.key === Qt.Key_Space) {
                        root.chooseTrait(traitRow.modelData.id,
                            traitRow.modelData.currentValue !== true);
                        event.accepted = true;
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.traitLabel(traitRow.modelData)
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    color: Theme.textMid
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: traitRow.modelData.currentValue === true ? "ON" : "OFF"
                    font.family: Theme.fontMono
                    font.pixelSize: 9
                    font.weight: 600
                    color: traitRow.modelData.currentValue === true ? Theme.accent : Theme.textDim
                }

                MouseArea {
                    id: traitMouse
                    anchors.fill: parent
                    enabled: root.editable && !root.sending
                    hoverEnabled: true
                    onClicked: root.chooseTrait(traitRow.modelData.id,
                        traitRow.modelData.currentValue !== true)
                }
            }
        }
    }

    Text {
        visible: root.draft.traitError !== ""
        width: parent.width
        text: root.draft.traitError ?? ""
        wrapMode: Text.WordWrap
        font.family: Theme.fontSans
        font.pixelSize: 9
        color: Theme.amber
    }

    Rectangle {
        id: promptBox

        width: parent.width
        height: Math.max(62, Math.min(112, promptEdit.contentHeight + 18))
        radius: 8
        color: /\bultrathink\b/i.test(promptEdit.text) ? Theme.accentBgSoft
            : Qt.rgba(0, 0, 0, 0.24)
        border.width: 1
        border.color: root.overLimit ? Theme.redBorder
            : promptEdit.activeFocus ? Theme.accentBgSoft : Theme.hairlineSoft

        Flickable {
            id: promptFlick
            anchors.left: parent.left
            anchors.right: sendButton.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 8
            anchors.rightMargin: 7
            contentWidth: width
            contentHeight: Math.max(height, promptEdit.contentHeight)
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            TextEdit {
                id: promptEdit

                property bool syncing: false

                width: promptFlick.width
                height: Math.max(promptFlick.height, contentHeight)
                enabled: root.editable && !root.sending
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                font.family: Theme.fontSans
                font.pixelSize: 11
                color: Theme.textHi
                selectionColor: Theme.accentBg
                selectedTextColor: Theme.textHi
                onTextChanged: {
                    if (!syncing && activeFocus)
                        root.persistPrompt(text);
                }
                onCursorRectangleChanged: {
                    if (cursorRectangle.y + cursorRectangle.height > promptFlick.contentY
                            + promptFlick.height)
                        promptFlick.contentY = cursorRectangle.y + cursorRectangle.height
                            - promptFlick.height;
                    else if (cursorRectangle.y < promptFlick.contentY)
                        promptFlick.contentY = cursorRectangle.y;
                }

                Keys.onPressed: event => {
                    if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                        return;
                    if (event.modifiers & Qt.ControlModifier)
                        root.insertNewline();
                    else if (root.sendEnabled && !root.sending && !root.overLimit
                            && promptEdit.text.trim() !== "")
                        root.sendRequested();
                    event.accepted = true;
                }

                Text {
                    visible: promptEdit.text === "" && !promptEdit.activeFocus
                    text: root.newThread ? "Describe the first task…" : "Send a follow-up…"
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    color: Theme.textFaint
                }
            }
        }

        Rectangle {
            id: sendButton

            anchors.right: parent.right
            anchors.rightMargin: 7
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 7
            width: Math.max(31, sendText.implicitWidth + 14)
            height: 25
            radius: 6
            color: sendMouse.containsMouse && sendMouse.enabled
                ? Qt.lighter(Theme.accent, 1.12) : Theme.accent
            opacity: sendMouse.enabled ? 1 : 0.35
            activeFocusOnTab: sendMouse.enabled

            Keys.onPressed: event => {
                if (!sendMouse.enabled)
                    return;
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                        || event.key === Qt.Key_Space) {
                    root.sendRequested();
                    event.accepted = true;
                }
            }

            Text {
                id: sendText
                anchors.centerIn: parent
                text: root.sending ? "…" : root.sendLabel
                font.family: Theme.fontSans
                font.pixelSize: 10
                font.weight: 650
                color: Theme.accentFg
            }

            MouseArea {
                id: sendMouse
                anchors.fill: parent
                enabled: root.sendEnabled && !root.sending && !root.overLimit
                    && promptEdit.text.trim() !== ""
                hoverEnabled: true
                onClicked: root.sendRequested()
            }
        }
    }

    Row {
        width: parent.width

        Text {
            text: root.overLimit ? "Prompt too long — open T3 Code"
                : "Enter to send · Ctrl+Enter for newline"
            font.family: Theme.fontSans
            font.pixelSize: 9
            color: root.overLimit ? Theme.redText : Theme.textDim
        }

        Item { width: Math.max(0, parent.width - parent.children[0].width - count.width); height: 1 }

        Text {
            id: count
            visible: promptEdit.text.length > 100000
            text: promptEdit.text.length + "/" + T3Code.maxPromptChars
            font.family: Theme.fontMono
            font.pixelSize: 9
            color: root.overLimit ? Theme.redText : Theme.textDim
        }
    }

    Connections {
        target: T3Code
        function onThreadDraftsChanged() { if (!root.newThread) root.syncPrompt(); }
        function onNewThreadDraftChanged() { if (root.newThread) root.syncPrompt(); }
    }

    Component.onCompleted: syncPrompt()
}
