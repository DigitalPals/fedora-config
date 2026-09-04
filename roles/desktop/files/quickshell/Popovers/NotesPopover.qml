pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/NotesHelpers.js" as NotesHelpers
import "../Common/PanelRegistryData.js" as PanelRegistry

// A compact Markdown notebook. Draft text belongs to this view only while it
// is focused; canonical records, persistence and the deletion buffer live in
// the Notes singleton so closing the Loader cannot lose them.
Surface {
    id: root

    focus: visible
    padding: Theme.surfacePadding
    spacing: 10
    implicitWidth: availableWidth > 0
        ? Math.min(Theme.popWidth, availableWidth) : Theme.popWidth

    property bool editing: false
    property string editingId: ""
    property int editorGeneration: 0
    property string observedTitle: ""
    property bool persistingTitle: false

    readonly property string statusText: Notes.error !== "" ? Notes.error
        : !Notes.ready ? "Loading…"
        : Notes.undoAvailable ? "Note deleted"
        : ""

    onActiveFocusChanged: {
        if (activeFocus && !editing)
            focusInitial();
    }

    function focusInitial() {
        Qt.callLater(() => {
            if (root.visible && !root.editing)
                addButton.forceActiveFocus();
        });
    }

    function setEditorText(body) {
        noteEdit.syncing = true;
        noteEdit.text = body;
        noteEdit.cursorPosition = noteEdit.text.length;
        noteEdit.syncing = false;
    }

    function setEditorTitle(title) {
        titleEdit.syncing = true;
        titleEdit.text = title;
        titleEdit.cursorPosition = titleEdit.text.length;
        titleEdit.syncing = false;
    }

    function syncEditorTitle() {
        if (editingId === "")
            return;
        const note = Notes.record(editingId);
        if (!note || note.title === observedTitle)
            return;
        observedTitle = note.title;
        if (!persistingTitle && titleEdit.text !== note.title)
            setEditorTitle(note.title);
    }

    function persistEditor() {
        if (!editing || noteEdit.syncing || NotesHelpers.isBlank(noteEdit.text))
            return;
        if (editingId === "") {
            editingId = Notes.add(noteEdit.text, titleEdit.text);
            const note = Notes.record(editingId);
            observedTitle = note ? note.title : "";
        } else {
            Notes.update(editingId, noteEdit.text);
        }
    }

    function persistTitle() {
        if (!editing || titleEdit.syncing)
            return;
        if (editingId !== "") {
            persistingTitle = true;
            Notes.updateTitle(editingId, titleEdit.text);
            const note = Notes.record(editingId);
            observedTitle = note ? note.title : "";
            persistingTitle = false;
        }
    }

    function beginNew() {
        if (!Notes.ready)
            return;
        finishEditing(false);
        editingId = "";
        setEditorText("");
        setEditorTitle("");
        observedTitle = "";
        editorGeneration++;
        editing = true;
        editorScope.hadFocus = false;
        Qt.callLater(noteEdit.forceActiveFocus);
    }

    function beginEdit(note) {
        if (!Notes.ready || !note || typeof note.id !== "string")
            return;
        if (editing && editingId === note.id) {
            noteEdit.forceActiveFocus();
            return;
        }
        finishEditing(false);
        editingId = note.id;
        setEditorText(note.body);
        setEditorTitle(note.title);
        observedTitle = note.title;
        editorGeneration++;
        editing = true;
        editorScope.hadFocus = false;
        Qt.callLater(noteEdit.forceActiveFocus);
    }

    function finishEditing(restoreFocus) {
        if (!editing)
            return;
        const id = editingId;
        const body = noteEdit.text;
        const autoGenerateTitle = NotesHelpers.shouldAutoGenerateTitle(
            titleEdit.text, Settings.modOpts.notes.titleProvider);
        editorGeneration++;
        editing = false;
        editingId = "";
        editorScope.hadFocus = false;
        if (id !== "") {
            if (NotesHelpers.isBlank(body))
                Notes.remove(id);
            else {
                Notes.update(id, body);
                if (autoGenerateTitle)
                    Notes.requestTitle(id);
            }
        }
        Notes.flush();
        if (restoreFocus)
            focusInitial();
    }

    function deleteEditing() {
        const id = editingId;
        editorGeneration++;
        editing = false;
        editingId = "";
        editorScope.hadFocus = false;
        if (id !== "")
            Notes.remove(id);
        Notes.flush();
        focusInitial();
    }

    function deleteCard(id) {
        finishEditing(false);
        Notes.remove(id);
        Notes.flush();
        focusInitial();
    }

    function applyFormat(action) {
        if (!editing)
            return;
        const transformed = NotesHelpers.transformMarkdown(noteEdit.text,
            noteEdit.selectionStart, noteEdit.selectionEnd, action);
        noteEdit.syncing = true;
        noteEdit.text = transformed.text;
        noteEdit.cursorPosition = transformed.cursorPosition;
        noteEdit.select(transformed.selectionStart, transformed.selectionEnd);
        noteEdit.syncing = false;
        persistEditor();
        noteEdit.forceActiveFocus();
    }

    function handleEscape(): bool {
        if (!editing)
            return false;
        finishEditing(true);
        return true;
    }

    component NoteIconButton: Rectangle {
        id: button

        property string symbol: ""
        property string actionName: ""
        property color tint: Theme.textMid
        property int controlSize: 30
        signal triggered

        width: controlSize
        height: controlSize
        radius: Theme.rowRadius
        color: buttonMouse.containsMouse || activeFocus
            ? Theme.hoverFillStrong : "transparent"
        border.width: activeFocus ? 1 : 0
        border.color: Theme.accent
        activeFocusOnTab: enabled && visible
        Accessible.role: Accessible.Button
        Accessible.name: actionName
        Accessible.onPressAction: button.triggered()

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                button.triggered();
                event.accepted = true;
            }
        }

        Sym {
            anchors.centerIn: parent
            name: button.symbol
            size: Theme.iconMedium
            color: button.tint
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            enabled: button.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.triggered()
        }
    }

    Item {
        width: parent.width
        height: 34

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Sym {
                anchors.verticalCenter: parent.verticalCenter
                name: "sticky_note_2"
                size: Theme.iconMedium
                fill: Notes.count > 0 ? 1 : 0
                color: Theme.accent
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Notes"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontHeading
                font.weight: Theme.weightBold
                color: Theme.textHi
            }
        }

        NoteIconButton {
            id: addButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            symbol: "add"
            actionName: "Add note"
            tint: Theme.accent
            enabled: Notes.ready
            onTriggered: root.beginNew()
        }
    }

    Item {
        width: parent.width
        visible: root.statusText !== "" || Notes.undoAvailable
        height: visible ? 28 : 0

        Text {
            anchors.left: parent.left
            anchors.right: statusActions.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: root.statusText
            elide: Text.ElideRight
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: Notes.error !== "" ? Theme.redText : Theme.textLow
            Accessible.role: Notes.error !== ""
                ? Accessible.AlertMessage : Accessible.StaticText
            Accessible.name: root.statusText
        }

        Row {
            id: statusActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            ActionButton {
                visible: Notes.error !== ""
                label: "Retry"
                hPadding: 14
                tint: Theme.redText
                fill: Theme.redBgSoft
                onTriggered: Notes.retrySave()
            }

            ActionButton {
                visible: Notes.undoAvailable
                label: "Undo"
                hPadding: 14
                tint: Theme.accent
                fill: Theme.accentBgSoft
                onTriggered: Notes.undoDelete()
            }
        }
    }

    FocusScope {
        id: editorScope

        property bool hadFocus: false

        visible: root.editing
        width: parent.width
        height: visible ? 266 : 0
        onActiveFocusChanged: {
            if (activeFocus) {
                hadFocus = true;
            } else if (hadFocus && root.editing) {
                const lostGeneration = root.editorGeneration;
                Qt.callLater(() => {
                    if (root.editing
                            && root.editorGeneration === lostGeneration
                            && !editorScope.activeFocus)
                        root.finishEditing(false);
                });
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.cardRadius
            color: Theme.tile
            border.width: noteEdit.activeFocus ? 1 : 0
            border.color: Theme.accent

            Item {
                id: editorHeader
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                height: 28

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.editingId === "" ? "New note" : "Editing note"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    font.weight: Theme.weightSemibold
                    color: Theme.textLow
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    ActionButton {
                        visible: root.editingId !== ""
                            && Settings.modOpts.notes.titleProvider !== "off"
                        label: "Generate"
                        hPadding: 10
                        enabled: !Notes.titlePending(root.editingId)
                        onTriggered: {
                            root.persistEditor();
                            Notes.requestTitle(root.editingId);
                        }
                    }

                    NoteIconButton {
                        visible: root.editingId !== ""
                        controlSize: 28
                        symbol: "delete"
                        actionName: "Delete note"
                        tint: Theme.redText
                        onTriggered: root.deleteEditing()
                    }
                }
            }

            Rectangle {
                id: titleFrame
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: editorHeader.bottom
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                height: 32
                radius: Theme.rowRadius
                color: titleEdit.activeFocus ? Theme.hoverFillStrong : Theme.cardFill
                border.width: titleEdit.activeFocus ? 1 : 0
                border.color: Theme.accent

                TextInput {
                    id: titleEdit

                    property bool syncing: false

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    maximumLength: NotesHelpers.MAX_TITLE_LENGTH
                    selectByMouse: true
                    activeFocusOnTab: true
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontBody
                    font.weight: Theme.weightSemibold
                    color: Theme.textHi
                    selectionColor: Theme.accentBg
                    selectedTextColor: Theme.textHi
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Note title"
                    Accessible.description: "Editable plain-text title"
                    onTextEdited: root.persistTitle()

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.finishEditing(true);
                            event.accepted = true;
                        }
                    }

                    Text {
                        visible: titleEdit.text === ""
                        text: "Title"
                        font: titleEdit.font
                        color: Theme.textFaint
                    }
                }
            }

            Item {
                id: titleStatus
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: titleFrame.bottom
                anchors.leftMargin: 11
                anchors.rightMargin: 9
                readonly property string failure: root.editingId === "" ? ""
                    : Notes.titleError(root.editingId)
                readonly property bool pending: root.editingId !== ""
                    && Notes.titlePending(root.editingId)
                visible: pending || failure !== ""
                height: visible ? 25 : 0

                Text {
                    anchors.left: parent.left
                    anchors.right: retryTitleButton.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: titleStatus.pending ? "Generating title…" : titleStatus.failure
                    elide: Text.ElideRight
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontMicro
                    color: titleStatus.failure !== "" ? Theme.redText : Theme.textLow
                    Accessible.role: titleStatus.failure !== ""
                        ? Accessible.AlertMessage : Accessible.StaticText
                    Accessible.name: text
                }

                ActionButton {
                    id: retryTitleButton
                    visible: titleStatus.failure !== ""
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Retry title"
                    hPadding: 10
                    tint: Theme.redText
                    fill: Theme.redBgSoft
                    onTriggered: Notes.retryTitle(root.editingId)
                }
            }

            Flickable {
                id: editorFlick
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: titleStatus.bottom
                anchors.bottom: formatRow.top
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 3
                anchors.bottomMargin: 5
                contentWidth: width
                contentHeight: Math.max(height, noteEdit.contentHeight)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                TextEdit {
                    id: noteEdit

                    property bool syncing: false

                    width: editorFlick.width
                    height: Math.max(editorFlick.height, contentHeight)
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    persistentSelection: true
                    activeFocusOnTab: true
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontBody
                    color: Theme.textHi
                    selectionColor: Theme.accentBg
                    selectedTextColor: Theme.textHi
                    Accessible.role: Accessible.EditableText
                    Accessible.name: root.editingId === "" ? "New note" : "Edit note"
                    Accessible.description: "Markdown note"
                    onTextChanged: root.persistEditor()
                    onCursorRectangleChanged: {
                        if (cursorRectangle.y + cursorRectangle.height
                                > editorFlick.contentY + editorFlick.height)
                            editorFlick.contentY = cursorRectangle.y
                                + cursorRectangle.height - editorFlick.height;
                        else if (cursorRectangle.y < editorFlick.contentY)
                            editorFlick.contentY = cursorRectangle.y;
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.finishEditing(true);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab
                                && !(event.modifiers & Qt.ControlModifier)) {
                            titleEdit.forceActiveFocus();
                            event.accepted = true;
                        }
                    }

                    Text {
                        visible: noteEdit.text === ""
                        text: "Write a Markdown note…"
                        font: noteEdit.font
                        color: Theme.textFaint
                    }
                }
            }

            Row {
                id: formatRow
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 7
                spacing: 3

                NoteIconButton {
                    id: boldButton
                    symbol: "format_bold"
                    actionName: "Bold"
                    onTriggered: root.applyFormat("bold")
                }
                NoteIconButton {
                    symbol: "format_italic"
                    actionName: "Italic"
                    onTriggered: root.applyFormat("italic")
                }
                NoteIconButton {
                    symbol: "format_list_bulleted"
                    actionName: "Bulleted list"
                    onTriggered: root.applyFormat("bullet")
                }
                NoteIconButton {
                    symbol: "checklist"
                    actionName: "Checklist"
                    onTriggered: root.applyFormat("checklist")
                }
                NoteIconButton {
                    symbol: "link"
                    actionName: "Link"
                    onTriggered: root.applyFormat("link")
                }
                NoteIconButton {
                    symbol: "code"
                    actionName: "Inline code"
                    onTriggered: root.applyFormat("code")
                }
            }
        }
    }

    HDivider {
        visible: Notes.count > 0 || root.editing
        width: parent.width
        height: visible ? 1 : 0
    }

    Text {
        visible: Notes.ready && Notes.count === 0 && !root.editing
        width: parent.width
        height: visible ? 64 : 0
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        text: "No notes yet"
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontBody
        color: Theme.textFaint
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }

    Flickable {
        id: noteList

        width: parent.width
        height: Notes.count > 0
            ? Math.min(noteColumn.implicitHeight,
                Math.max(80, root.availableHeight - (root.editing ? 392 : 130))) : 0
        // Do not derive visibility from a height which is itself derived from
        // invisible descendants: that cycle leaves the first records at zero
        // height on some Qt versions. Count is the canonical visibility gate.
        visible: Notes.count > 0
        contentWidth: width
        contentHeight: noteColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: noteColumn
            width: parent.width
            spacing: 6

            Repeater {
                model: Notes.records

                delegate: Rectangle {
                    id: noteCard

                    required property var modelData
                    readonly property bool titleBusy: Notes.titlePending(modelData.id)
                    readonly property string titleFailure: Notes.titleError(modelData.id)

                    visible: modelData.id !== root.editingId
                    width: parent.width
                    height: visible ? Math.max(44, cardActions.implicitHeight + 12) : 0
                    radius: Theme.cardRadius
                    color: noteMouse.containsMouse || activeFocus
                        ? Theme.hoverFillStrong : Theme.tile
                    border.width: activeFocus ? 1 : 0
                    border.color: Theme.accent
                    activeFocusOnTab: visible
                    Accessible.role: Accessible.Button
                    Accessible.name: "Edit note: " + modelData.title
                    Accessible.description: titleBusy ? "Generating title"
                        : titleFailure
                    Accessible.onPressAction: root.beginEdit(modelData)

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                || event.key === Qt.Key_Space) {
                            root.beginEdit(noteCard.modelData);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Delete) {
                            root.deleteCard(noteCard.modelData.id);
                            event.accepted = true;
                        }
                    }

                    MouseArea {
                        id: noteMouse
                        anchors.left: parent.left
                        anchors.right: cardActions.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            noteCard.forceActiveFocus();
                            root.beginEdit(noteCard.modelData);
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.right: cardActions.left
                        anchors.leftMargin: 11
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: noteCard.modelData.title
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontBody
                        font.weight: Theme.weightSemibold
                        color: noteCard.titleFailure !== ""
                            ? Theme.redText : Theme.textHi
                    }

                    Row {
                        id: cardActions
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Item {
                            visible: noteCard.titleBusy
                            width: visible ? 30 : 0
                            height: 30
                            Accessible.role: Accessible.StaticText
                            Accessible.name: "Generating title"

                            Sym {
                                anchors.centerIn: parent
                                name: "progress_activity"
                                size: Theme.iconMedium
                                color: Theme.textLow
                            }
                        }

                        NoteIconButton {
                            visible: noteCard.titleFailure !== ""
                            symbol: "refresh"
                            actionName: "Retry title generation"
                            tint: Theme.accent
                            onTriggered: Notes.retryTitle(noteCard.modelData.id)
                        }

                        NoteIconButton {
                            symbol: "delete"
                            actionName: "Delete note"
                            tint: Theme.redText
                            onTriggered: root.deleteCard(noteCard.modelData.id)
                        }
                    }
                }
            }
        }

        ScrollChrome {
            anchors.fill: parent
            target: noteList
        }
    }

    Connections {
        target: Popouts

        function onChanged() {
            if (!Popouts.open || Popouts.currentName !== PanelRegistry.NOTES)
                root.finishEditing(false);
        }
    }

    Connections {
        target: Notes

        function onRecordsChanged() {
            if (root.editing)
                root.syncEditorTitle();
        }
    }

    Component.onCompleted: focusInitial()
    Component.onDestruction: finishEditing(false)
}
