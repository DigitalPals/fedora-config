pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "NotesHelpers.js" as NotesHelpers
import "PanelRegistryData.js" as PanelRegistry

// Process-wide Markdown notes with a strict, atomic local state file. The
// editor view is rebuilt whenever its popout closes, so all durable and undo
// state lives here rather than in NotesPopover.
Singleton {
    id: root

    readonly property string filePath:
        Quickshell.env("HOME") + "/.local/state/quickshell/notes.json"

    property var records: []
    readonly property int count: records.length
    property bool ready: false
    property bool dirty: false
    property bool writeInFlight: false
    property bool flushRequested: false
    property string writeSnapshot: ""
    property string error: ""
    property string errorKind: ""
    property double lastSavedAt: 0
    property var deletedRecord: null
    property int idCounter: 0
    property bool initialLoadHandled: false

    readonly property bool saving: writeInFlight
        || (dirty && errorKind === "")
    readonly property bool undoAvailable: deletedRecord !== null

    function canMutate() {
        return ready && errorKind !== "load";
    }

    function record(id) {
        return NotesHelpers.findRecord(records, id);
    }

    function nextId() {
        let id = "";
        do {
            idCounter++;
            id = "note-" + Date.now().toString(36) + "-"
                + idCounter.toString(36) + "-"
                + Math.floor(Math.random() * 0x100000000).toString(36);
        } while (record(id) !== null);
        return id;
    }

    function markDirty() {
        dirty = true;
        if (errorKind === "")
            saveTimer.restart();
    }

    function add(body) {
        if (!canMutate() || NotesHelpers.isBlank(body))
            return "";
        const now = Date.now();
        const id = nextId();
        const result = NotesHelpers.addRecord(records, body, id, now);
        if (!result.changed)
            return "";
        records = result.records;
        markDirty();
        return id;
    }

    function update(id, body) {
        if (!canMutate())
            return false;
        if (NotesHelpers.isBlank(body))
            return remove(id);
        const result = NotesHelpers.updateRecord(records, id, body, Date.now());
        if (!result.changed)
            return false;
        records = result.records;
        markDirty();
        return true;
    }

    function remove(id) {
        if (!canMutate())
            return false;
        const result = NotesHelpers.removeRecord(records, id);
        if (!result.changed)
            return false;
        records = result.records;
        deletedRecord = result.deleted;
        undoTimer.restart();
        markDirty();
        return true;
    }

    function undoDelete() {
        if (!canMutate() || deletedRecord === null)
            return false;
        const result = NotesHelpers.restoreDeleted(records, deletedRecord);
        if (!result.changed)
            return false;
        undoTimer.stop();
        deletedRecord = null;
        records = result.records;
        markDirty();
        return true;
    }

    function retrySave() {
        if (!ready || errorKind === "load") {
            error = "";
            errorKind = "";
            initialLoadHandled = false;
            store.reload();
            return;
        }
        error = "";
        errorKind = "";
        flush();
    }

    function flush() {
        saveTimer.stop();
        if (!dirty)
            return;
        if (writeInFlight) {
            flushRequested = true;
            return;
        }
        saveNow();
    }

    function saveNow() {
        if (!ready || !dirty || writeInFlight || errorKind !== "")
            return;
        writeSnapshot = NotesHelpers.serializeState(records);
        writeInFlight = true;
        try {
            store.setText(writeSnapshot);
        } catch (saveException) {
            handleSaveFailure(FileViewError.Unknown);
            console.warn("notes save threw:", saveException);
        }
    }

    function handleSaveSucceeded() {
        const completed = writeSnapshot;
        writeSnapshot = "";
        writeInFlight = false;
        error = "";
        errorKind = "";
        lastSavedAt = Date.now();
        const changedWhileSaving = NotesHelpers.serializeState(records) !== completed;
        dirty = changedWhileSaving;
        if (!changedWhileSaving) {
            flushRequested = false;
            return;
        }
        if (flushRequested) {
            flushRequested = false;
            Qt.callLater(root.saveNow);
        } else {
            saveTimer.restart();
        }
    }

    function handleSaveFailure(fileError) {
        writeSnapshot = "";
        writeInFlight = false;
        flushRequested = false;
        dirty = true;
        errorKind = "save";
        error = "Could not save notes";
        console.warn("notes save failed:", FileViewError.toString(fileError));
    }

    function applyLoaded(rawText) {
        initialLoadHandled = true;
        const parsed = NotesHelpers.parseState(rawText);
        if (parsed.status === "corrupt") {
            ready = false;
            dirty = false;
            saveTimer.stop();
            errorKind = "load";
            error = "Notes file is malformed and was left untouched";
            console.warn("notes load blocked:", parsed.error, "at", filePath);
            return;
        }
        records = parsed.records;
        ready = true;
        dirty = false;
        error = "";
        errorKind = "";
    }

    function handleLoadFailure(fileError) {
        initialLoadHandled = true;
        if (fileError === FileViewError.FileNotFound) {
            records = [];
            ready = true;
            dirty = false;
            error = "";
            errorKind = "";
            return;
        }
        ready = false;
        dirty = false;
        saveTimer.stop();
        errorKind = "load";
        error = "Could not load notes; the file was left untouched";
        console.warn("notes load failed:", FileViewError.toString(fileError));
    }

    Timer {
        id: saveTimer
        interval: 400
        onTriggered: root.saveNow()
    }

    Timer {
        id: undoTimer
        interval: 5000
        onTriggered: root.deletedRecord = null
    }

    FileView {
        id: store
        path: root.filePath
        printErrors: false
        atomicWrites: true
        blockWrites: true
        blockLoading: true
        onLoaded: root.applyLoaded(text())
        onLoadFailed: error => root.handleLoadFailure(error)
        onSaved: root.handleSaveSucceeded()
        onSaveFailed: error => root.handleSaveFailure(error)
    }

    // Closing or switching away from Notes is a persistence boundary even if
    // the panel instance has not been destroyed by its exit animation yet.
    Connections {
        target: Popouts

        function onChanged() {
            if (!Popouts.open || Popouts.currentName !== PanelRegistry.NOTES)
                root.flush();
        }
    }

    Component.onCompleted: {
        if (!initialLoadHandled) {
            const initialText = store.text();
            if (!initialLoadHandled && store.loaded)
                applyLoaded(initialText);
        }
    }
}
