import QtQuick
import "../Common"

// Text-only composer with a local disclosure for provider/model/runtime/mode
// and every model trait advertised by server.getConfig. The singleton owns
// all draft values; disclosure state lasts only as long as this page instance.
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
    // A picker menu has to escape both the settings card's and this
    // composer's stacking contexts to cover controls declared after it.
    z: settingsPresentation.activePicker !== null ? 100 : 0

    QtObject {
        id: settingsPresentation

        property bool expanded: false
        property Item activePicker: null
        property string activePickerGroup: ""
        readonly property bool narrow: root.width < 360
        readonly property var accessOptions: [
            { id: "approval-required", label: "Ask first" },
            { id: "auto-accept-edits", label: "Auto edits" },
            { id: "auto", label: "Auto" },
            { id: "full-access", label: "Full access" }
        ]
        readonly property var interactionOptions: [
            { id: "default", label: "Default" },
            { id: "plan", label: "Plan" }
        ]

        function trackPicker(picker, group) {
            if (picker.expanded) {
                if (activePicker !== null && activePicker !== picker)
                    activePicker.expanded = false;
                activePicker = picker;
                activePickerGroup = group;
            } else if (activePicker === picker) {
                activePicker = null;
                activePickerGroup = "";
            }
        }

        onExpandedChanged: {
            if (!expanded && activePicker !== null)
                activePicker.expanded = false;
        }

        onActivePickerChanged: {
            if (activePicker === null)
                activePickerGroup = "";
        }

        function settingId(option) {
            if (!option)
                return "";
            return String(option.id ?? option.instanceId ?? option.slug ?? option.value ?? "");
        }

        function settingLabel(option) {
            if (!option)
                return "";
            return String(option.label ?? option.displayName ?? option.name ?? option.shortName
                ?? settingId(option));
        }

        function displaySettingValue(value, fallback) {
            const text = String(value ?? "").trim();
            if (text === "")
                return fallback;
            return text.replace(/[-_]+/g, " ").replace(/\b\w/g,
                character => character.toUpperCase());
        }

        function selectedSettingLabel(options, value, fallback) {
            const found = (Array.isArray(options) ? options : [])
                .find(option => settingId(option) === value);
            return found ? settingLabel(found) : displaySettingValue(value, fallback);
        }

        // Labels combined into the compact disclosure summary. Empty strings
        // are omitted so unsupported controls consume no width.
        function reasoningSummary() {
            const descriptor = (Array.isArray(root.traits) ? root.traits : [])
                .find(candidate => root.traitLabel(candidate) === "Reasoning");
            if (!descriptor)
                return "";
            if (descriptor.type === "boolean")
                return "Reasoning " + (descriptor.currentValue === true ? "On" : "Off");
            return "Reasoning " + selectedSettingLabel(descriptor.options,
                String(descriptor.currentValue ?? ""), "—");
        }

        function accessSummary() {
            return selectedSettingLabel(accessOptions,
                String(root.draft?.runtimeMode ?? "full-access"), "Unavailable");
        }

        function providerModelSummary() {
            const provider = selectedSettingLabel(root.providers,
                String(root.draft?.instanceId ?? ""), "Provider unavailable");
            const slug = String(root.draft?.model ?? "");
            const found = (Array.isArray(root.models) ? root.models : [])
                .find(option => settingId(option) === slug);
            const model = found
                ? String(found.shortName || found.name || settingLabel(found))
                : displaySettingValue(slug, "");
            return model !== "" ? provider + " · " + model : provider;
        }

        function modeSummary() {
            if (!root.showInteraction)
                return "";
            return String(root.draft?.interactionMode ?? "default") === "plan"
                ? "Plan mode" : "Default mode";
        }

        function compactSummary() {
            const parts = [providerModelSummary(), reasoningSummary(), modeSummary()]
                .filter(value => value !== "");
            return parts.join(" · ");
        }
    }

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
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontBody
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
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontBody
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
            width: Math.max(31, sendText.implicitWidth + 18)
            height: Theme.controlHeight
            radius: 7
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
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontSecondary
                font.weight: Theme.weightSemibold
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

    Rectangle {
        id: settingsCard

        width: parent.width
        height: settingsColumn.implicitHeight + (settingsPresentation.expanded ? 2 : 0)
        z: settingsPresentation.activePicker !== null ? 100 : 0
        radius: 8
        color: settingsPresentation.expanded ? Theme.cardFill : "transparent"
        border.width: settingsPresentation.expanded ? 1 : 0
        border.color: Theme.hairlineSoft

        Column {
            id: settingsColumn

            x: settingsPresentation.expanded ? 1 : 0
            y: settingsPresentation.expanded ? 1 : 0
            width: parent.width - (settingsPresentation.expanded ? 2 : 0)

            // Keep the collapsed state to one footer-like row. The detailed
            // controls remain available without competing with the prompt.
            Rectangle {
                id: settingsHeader

                width: parent.width
                height: Theme.controlHeight
                radius: 7
                color: settingsMouse.containsMouse ? Theme.hoverFillStrong : "transparent"
                activeFocusOnTab: true
                border.width: activeFocus ? 1 : 0
                border.color: Theme.accent

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                            || event.key === Qt.Key_Space) {
                        settingsPresentation.expanded = !settingsPresentation.expanded;
                        event.accepted = true;
                    }
                }

                Text {
                    id: settingsChevron

                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.top: parent.top
                    anchors.topMargin: 9
                    text: settingsPresentation.expanded ? "▾" : "▸"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontCaption
                    color: settingsPresentation.expanded ? Theme.accent : Theme.textLow
                }

                Text {
                    id: settingsTitle

                    anchors.left: settingsChevron.right
                    anchors.leftMargin: 6
                    anchors.verticalCenter: settingsChevron.verticalCenter
                    text: "Run settings"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontSecondary
                    font.weight: Theme.weightSemibold
                    color: Theme.textHi
                }

                Text {
                    visible: !settingsPresentation.expanded
                    anchors.left: settingsTitle.right
                    anchors.leftMargin: 8
                    anchors.right: accessChip.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: settingsChevron.verticalCenter
                    text: settingsPresentation.compactSummary()
                    elide: Text.ElideRight
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textDim
                }

                Rectangle {
                    id: accessChip

                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: settingsChevron.verticalCenter
                    width: accessText.implicitWidth + 18
                    height: Theme.controlHeight
                    radius: 5
                    color: root.draft?.runtimeMode === "full-access"
                        ? Theme.amberBg : Theme.hoverFill

                    Text {
                        id: accessText
                        anchors.centerIn: parent
                        text: settingsPresentation.accessSummary()
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontCaption
                        font.weight: Theme.weightSemibold
                        color: root.draft?.runtimeMode === "full-access"
                            ? Theme.amber : Theme.textLow
                    }
                }

                MouseArea {
                    id: settingsMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        settingsHeader.forceActiveFocus();
                        settingsPresentation.expanded = !settingsPresentation.expanded;
                    }
                }
            }

            Item {
                id: settingsBody

                visible: settingsPresentation.expanded
                width: parent.width
                height: settingsFields.implicitHeight + 15

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 7
                    anchors.right: parent.right
                    anchors.rightMargin: 7
                    anchors.top: parent.top
                    height: 1
                    color: Theme.hairlineSoft
                }

                Column {
                    id: settingsFields

                    x: 7
                    y: 8
                    width: parent.width - 14
                    spacing: 5

                    Flow {
                        id: providerModelFields

                        width: parent.width
                        spacing: 5
                        z: settingsPresentation.activePickerGroup === "provider-model" ? 100 : 0

                        T3Picker {
                            id: providerPicker

                            width: settingsPresentation.narrow
                                ? parent.width : (parent.width - 5) / 2
                            label: "Provider"
                            value: root.draft.instanceId ?? ""
                            options: root.providers
                            openUpward: !root.newThread
                            enabled: root.editable && !root.sending && options.length > 0
                            onSelected: value => root.chooseProvider(value)
                            onExpandedChanged: settingsPresentation.trackPicker(
                                providerPicker, "provider-model")
                        }

                        T3Picker {
                            id: modelPicker

                            width: settingsPresentation.narrow
                                ? parent.width : (parent.width - 5) / 2
                            label: "Model"
                            value: root.draft.model ?? ""
                            options: root.models
                            openUpward: !root.newThread
                            menuRows: 8
                            enabled: root.editable && !root.sending && options.length > 0
                            onSelected: value => root.chooseModel(value)
                            onExpandedChanged: settingsPresentation.trackPicker(
                                modelPicker, "provider-model")
                        }
                    }

                    Flow {
                        id: runtimeFields

                        width: parent.width
                        spacing: 5
                        z: settingsPresentation.activePickerGroup === "runtime" ? 100 : 0

                        T3Picker {
                            id: accessPicker

                            width: settingsPresentation.narrow || !root.showInteraction
                                ? parent.width : (parent.width - 5) / 2
                            label: "Access"
                            value: root.draft.runtimeMode ?? "full-access"
                            valueColor: root.draft?.runtimeMode === "full-access"
                                ? Theme.amber : Theme.textMid
                            options: settingsPresentation.accessOptions
                            openUpward: !root.newThread
                            enabled: root.editable && !root.sending
                            onSelected: value => root.chooseRuntime(value)
                            onExpandedChanged: settingsPresentation.trackPicker(
                                accessPicker, "runtime")
                        }

                        T3Picker {
                            id: interactionPicker

                            visible: root.showInteraction
                            width: settingsPresentation.narrow
                                ? parent.width : (parent.width - 5) / 2
                            label: "Mode"
                            value: root.draft.interactionMode ?? "default"
                            options: settingsPresentation.interactionOptions
                            openUpward: !root.newThread
                            enabled: root.editable && !root.sending
                            onSelected: value => root.chooseInteraction(value)
                            onExpandedChanged: settingsPresentation.trackPicker(
                                interactionPicker, "runtime")
                        }
                    }

                    Flow {
                        id: traitFields

                        visible: root.traits.length > 0
                        width: parent.width
                        spacing: 5
                        z: settingsPresentation.activePickerGroup === "traits" ? 100 : 0

                        Repeater {
                            model: root.traits

                            delegate: Item {
                                id: traitRow

                                required property var modelData
                                width: settingsPresentation.narrow
                                    ? parent.width : (parent.width - 5) / 2
                                height: modelData.type === "select" ? 34 : 28
                                z: traitPicker.expanded ? 100 : 0

                                T3Picker {
                                    id: traitPicker

                                    visible: traitRow.modelData.type === "select"
                                    anchors.fill: parent
                                    label: root.traitLabel(traitRow.modelData)
                                    value: traitRow.modelData.currentValue ?? ""
                                    options: traitRow.modelData.options ?? []
                                    enabled: root.editable && !root.sending
                                    onSelected: value => root.chooseTrait(
                                        traitRow.modelData.id, value)
                                    onExpandedChanged: settingsPresentation.trackPicker(
                                        traitPicker, "traits")
                                }

                                Rectangle {
                                    id: traitToggle

                                    visible: traitRow.modelData.type === "boolean"
                                    anchors.fill: parent
                                    radius: 6
                                    color: traitMouse.containsMouse && root.editable
                                        ? Theme.hoverFillStrong : Theme.hoverFill
                                    opacity: root.editable && !root.sending ? 1 : 0.48
                                    activeFocusOnTab: root.editable && !root.sending
                                    border.width: activeFocus ? 1 : 0
                                    border.color: Theme.accent

                                    Keys.onPressed: event => {
                                        if (!root.editable || root.sending)
                                            return;
                                        if (event.key === Qt.Key_Return
                                                || event.key === Qt.Key_Enter
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
                                        font.family: Theme.fontMenu
                                        font.pixelSize: Theme.fontSecondary
                                        color: Theme.textMid
                                    }

                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: traitRow.modelData.currentValue === true ? "ON" : "OFF"
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontCaption
                                        font.weight: Theme.weightSemibold
                                        color: traitRow.modelData.currentValue === true
                                            ? Theme.accent : Theme.textDim
                                    }

                                    MouseArea {
                                        id: traitMouse

                                        anchors.fill: parent
                                        enabled: root.editable && !root.sending
                                        hoverEnabled: true
                                        onClicked: {
                                            traitToggle.forceActiveFocus();
                                            root.chooseTrait(traitRow.modelData.id,
                                                traitRow.modelData.currentValue !== true);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Text {
        visible: root.draft.traitError !== ""
        width: parent.width
        text: root.draft.traitError ?? ""
        wrapMode: Text.WordWrap
        lineHeight: Theme.proseLineHeight
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        color: Theme.amber
    }

    Row {
        width: parent.width

        Text {
            text: root.overLimit ? "Prompt too long — open T3 Code"
                : "Enter to send · Ctrl+Enter for newline"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: root.overLimit ? Theme.redText : Theme.textDim
        }

        Item { width: Math.max(0, parent.width - parent.children[0].width - count.width); height: 1 }

        Text {
            id: count
            visible: promptEdit.text.length > 100000
            text: promptEdit.text.length + "/" + T3Code.maxPromptChars
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontCaption
            color: root.overLimit ? Theme.redText : Theme.textDim
        }
    }

    Connections {
        target: T3Code
        function onThreadDraftsChanged() { if (!root.newThread) root.syncPrompt(); }
        function onNewThreadDraftChanged() { if (root.newThread) root.syncPrompt(); }
    }

    Component.onCompleted: {
        settingsPresentation.expanded = false;
        syncPrompt();
    }
}
