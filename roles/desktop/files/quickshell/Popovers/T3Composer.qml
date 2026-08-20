pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

// T3's composer is one recognisable glass surface: prompt above, contextual
// controls and a round send action below. Detailed run settings unfold as a
// compact drawer attached to that surface instead of becoming another form.
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
    readonly property bool showInteraction: draft.modeFixed !== true
        && T3Code.providerShowsInteraction(draft.instanceId)
    readonly property bool overLimit: promptEdit.text.length > T3Code.maxPromptChars
    readonly property bool ultrathink: /\bultrathink\b/i.test(promptEdit.text)
    readonly property string actionKind: newThread ? "new" : "prompt"
    readonly property string actionThreadId: newThread ? "" : threadId
    readonly property bool sending: T3Code.actionPending(actionKind, actionThreadId, "")

    spacing: 4
    z: settingsPresentation.activePicker !== null || settingsPresentation.expanded ? 100 : 0

    QtObject {
        id: settingsPresentation

        property bool expanded: false
        property Item activePicker: null
        property string activePickerGroup: ""
        readonly property bool narrow: root.width < 400
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

        function reasoningSummary() {
            const descriptor = (Array.isArray(root.traits) ? root.traits : [])
                .find(candidate => root.traitLabel(candidate) === "Reasoning");
            if (!descriptor)
                return "";
            if (descriptor.type === "boolean")
                return descriptor.currentValue === true ? "Reasoning on" : "Reasoning off";
            return selectedSettingLabel(descriptor.options,
                String(descriptor.currentValue ?? ""), "");
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
                ? "Plan" : "Default";
        }

        function compactSummary() {
            const parts = [providerModelSummary(), modeSummary(), reasoningSummary()]
                .filter(value => value !== "");
            return parts.join(" · ");
        }

        function accessibleSummary() {
            return compactSummary() + " · Access: " + accessSummary();
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
        id: settingsDrawer
        visible: settingsPresentation.expanded
        width: parent.width
        height: settingsDrawerColumn.implicitHeight + 16
        z: settingsPresentation.activePicker !== null ? 200 : 1
        radius: T3Theme.panelRadius
        color: T3Theme.overlay
        border.width: 1
        border.color: T3Theme.borderStrong

        Column {
            id: settingsDrawerColumn
            x: 8
            y: 8
            width: parent.width - 16
            spacing: 6

            Item {
                width: parent.width
                height: 28

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7

                    Sym {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "tune"
                        size: Theme.iconSmall
                        color: T3Theme.accent
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Run settings"
                        font.family: T3Theme.fontSans
                        font.pixelSize: Theme.fontSecondary
                        font.weight: Theme.weightSemibold
                        color: T3Theme.textPrimary
                    }
                }

                IconButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    controlSize: 28
                    symbol: "close"
                    accessibleName: "Close run settings"
                    onTriggered: settingsPresentation.expanded = false
                }
            }

            Flow {
                id: providerModelFields
                width: parent.width
                spacing: 5
                z: settingsPresentation.activePickerGroup === "provider-model" ? 100 : 0

                T3Picker {
                    id: providerPicker
                    width: settingsPresentation.narrow ? parent.width : (parent.width - 5) / 2
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
                    width: settingsPresentation.narrow ? parent.width : (parent.width - 5) / 2
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
                        ? T3Theme.amber : T3Theme.textSecondary
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
                    width: settingsPresentation.narrow ? parent.width : (parent.width - 5) / 2
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
                        width: settingsPresentation.narrow ? parent.width : (parent.width - 5) / 2
                        height: modelData.type === "select" ? 34 : 30
                        z: traitPicker.expanded ? 100 : 0

                        T3Picker {
                            id: traitPicker
                            visible: traitRow.modelData.type === "select"
                            anchors.fill: parent
                            label: root.traitLabel(traitRow.modelData)
                            value: traitRow.modelData.currentValue ?? ""
                            options: traitRow.modelData.options ?? []
                            enabled: root.editable && !root.sending
                            onSelected: value => root.chooseTrait(traitRow.modelData.id, value)
                            onExpandedChanged: settingsPresentation.trackPicker(
                                traitPicker, "traits")
                        }

                        Rectangle {
                            id: traitToggle
                            visible: traitRow.modelData.type === "boolean"
                            anchors.fill: parent
                            radius: T3Theme.controlRadius
                            color: traitMouse.containsMouse && root.editable
                                ? T3Theme.hoverStrong : T3Theme.surfaceRaised
                            Accessible.role: Accessible.CheckBox
                            Accessible.name: root.traitLabel(traitRow.modelData)
                            Accessible.checked: traitRow.modelData.currentValue === true
                            opacity: root.editable && !root.sending ? 1 : 0.48
                            activeFocusOnTab: root.editable && !root.sending
                            border.width: activeFocus ? 1 : 0
                            border.color: T3Theme.focus

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
                                font.family: T3Theme.fontSans
                                font.pixelSize: Theme.fontSecondary
                                color: T3Theme.textSecondary
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.rightMargin: 7
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28
                                height: 16
                                radius: 8
                                color: traitRow.modelData.currentValue === true
                                    ? T3Theme.accent : T3Theme.borderStrong

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: traitRow.modelData.currentValue === true ? parent.width - width - 3 : 3
                                    width: 10
                                    height: 10
                                    radius: 5
                                    color: T3Theme.accentForeground

                                    Behavior on x {
                                        NumberAnimation {
                                            duration: T3Theme.fastDuration
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: traitMouse
                                anchors.fill: parent
                                enabled: root.editable && !root.sending
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
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

            Text {
                visible: root.draft.traitError !== ""
                width: parent.width
                text: root.draft.traitError ?? ""
                wrapMode: Text.WordWrap
                font.family: T3Theme.fontSans
                font.pixelSize: Theme.fontCaption
                color: T3Theme.amber
            }
        }
    }

    Rectangle {
        id: composerShell
        width: parent.width
        height: composerContent.implicitHeight + 20
        radius: T3Theme.composerRadius
        color: T3Theme.composerGlass
        border.width: 1
        border.color: root.overLimit ? T3Theme.redBorder
            : promptEdit.activeFocus ? T3Theme.focus : T3Theme.borderStrong

        Behavior on border.color {
            ColorAnimation { duration: T3Theme.fastDuration }
        }

        Rectangle {
            visible: root.ultrathink
            anchors.fill: parent
            radius: parent.radius
            color: T3Theme.accentSubtle
        }

        Column {
            id: composerContent
            x: 10
            y: 10
            width: parent.width - 20
            spacing: 7

            Item {
                id: promptBox
                width: parent.width
                height: Math.max(58, Math.min(118, promptEdit.contentHeight + 8))

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
                        enabled: root.editable && !root.sending
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        Accessible.description: "Enter to send. Control Enter inserts a newline."
                        font.family: T3Theme.fontSans
                        font.pixelSize: Theme.fontBody
                        color: T3Theme.textPrimary
                        selectionColor: T3Theme.accentSoft
                        selectedTextColor: T3Theme.textPrimary
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
                            visible: promptEdit.text === ""
                            text: "Ask anything…"
                            font.family: T3Theme.fontSans
                            font.pixelSize: Theme.fontBody
                            color: T3Theme.textFaint
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: T3Theme.border
            }

            Item {
                width: parent.width
                height: Theme.inlineActionHeight

                Rectangle {
                    id: settingsButton
                    anchors.left: parent.left
                    anchors.right: accessChip.visible ? accessChip.left : sendButton.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    height: Theme.inlineActionHeight
                    radius: T3Theme.controlRadius
                    color: settingsMouse.containsMouse || settingsPresentation.expanded
                        ? T3Theme.hoverStrong : "transparent"
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: "Run settings"
                    Accessible.description: settingsPresentation.accessibleSummary()
                    Accessible.onPressAction:
                        settingsPresentation.expanded = !settingsPresentation.expanded
                    border.width: activeFocus ? 1 : 0
                    border.color: T3Theme.focus

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                || event.key === Qt.Key_Space) {
                            settingsPresentation.expanded = !settingsPresentation.expanded;
                            event.accepted = true;
                        }
                    }

                    Sym {
                        anchors.left: parent.left
                        anchors.leftMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        name: "tune"
                        size: Theme.iconSmall
                        symWeight: 450
                        color: settingsPresentation.expanded
                            ? T3Theme.accent : T3Theme.textFaint
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 28
                        anchors.right: parent.right
                        anchors.rightMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        text: settingsPresentation.compactSummary()
                        elide: Text.ElideRight
                        font.family: T3Theme.fontSans
                        font.pixelSize: Theme.fontCaption
                        color: T3Theme.textMuted
                    }

                    MouseArea {
                        id: settingsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            settingsButton.forceActiveFocus();
                            settingsPresentation.expanded = !settingsPresentation.expanded;
                        }
                    }
                }

                Rectangle {
                    id: accessChip
                    visible: root.width >= 405
                    anchors.right: sendButton.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(104, accessText.implicitWidth + 18)
                    height: Theme.chipInnerHeight
                    radius: height / 2
                    color: root.draft?.runtimeMode === "full-access"
                        ? T3Theme.amberSoft : T3Theme.hover
                    activeFocusOnTab: visible
                    Accessible.role: Accessible.Button
                    Accessible.name: "Access: " + settingsPresentation.accessSummary()
                    Accessible.onPressAction: settingsPresentation.expanded = true
                    border.width: activeFocus ? 1 : 0
                    border.color: T3Theme.focus

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                || event.key === Qt.Key_Space) {
                            settingsPresentation.expanded = true;
                            event.accepted = true;
                        }
                    }

                    Text {
                        id: accessText
                        anchors.centerIn: parent
                        width: Math.min(90, implicitWidth)
                        text: settingsPresentation.accessSummary()
                        elide: Text.ElideRight
                        font.family: T3Theme.fontSans
                        font.pixelSize: Theme.fontCaption
                        font.weight: Theme.weightMedium
                        color: root.draft?.runtimeMode === "full-access"
                            ? T3Theme.amber : T3Theme.textFaint
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: settingsPresentation.expanded = true
                    }
                }

                Rectangle {
                    id: sendButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.inlineActionHeight
                    height: Theme.inlineActionHeight
                    radius: width / 2
                    color: sendMouse.containsMouse && sendMouse.enabled
                        ? T3Theme.accentHover : T3Theme.accent
                    opacity: sendMouse.enabled ? 1 : 0.32
                    activeFocusOnTab: sendMouse.enabled
                    Accessible.role: Accessible.Button
                    Accessible.name: root.sendLabel
                    Accessible.onPressAction: root.sendRequested()
                    border.width: activeFocus ? 2 : 0
                    border.color: T3Theme.accentForeground

                    Keys.onPressed: event => {
                        if (!sendMouse.enabled)
                            return;
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                || event.key === Qt.Key_Space) {
                            root.sendRequested();
                            event.accepted = true;
                        }
                    }

                    Sym {
                        anchors.centerIn: parent
                        name: root.sending ? "more_horiz" : "arrow_upward"
                        size: Theme.iconMedium
                        symWeight: 600
                        color: T3Theme.accentForeground
                    }

                    MouseArea {
                        id: sendMouse
                        anchors.fill: parent
                        enabled: root.sendEnabled && !root.sending && !root.overLimit
                            && promptEdit.text.trim() !== ""
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.sendRequested()
                    }
                }
            }

            Text {
                visible: root.overLimit
                width: parent.width
                text: "Prompt too long — open T3 Code"
                font.family: T3Theme.fontSans
                font.pixelSize: Theme.fontCaption
                color: T3Theme.red
            }
        }
    }

    // Updating a draft replaces the singleton's map and emits its change
    // signal before every dependent binding is guaranteed to have observed
    // the replacement. Resync on the next event-loop turn: an edit originating
    // here then compares equal and leaves the cursor alone, while an external
    // clear/restore still reaches the editor.
    Timer {
        id: promptSyncTimer
        interval: 0
        onTriggered: root.syncPrompt()
    }

    Connections {
        target: T3Code
        function onThreadDraftsChanged() {
            if (!root.newThread)
                promptSyncTimer.restart();
        }
        function onNewThreadDraftChanged() {
            if (root.newThread)
                promptSyncTimer.restart();
        }
    }

    Component.onCompleted: {
        settingsPresentation.expanded = false;
        syncPrompt();
    }
}
