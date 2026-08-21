pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Canonical reminder state lives in the helper's atomic JSON records. This
// singleton is a live read model for the bar and manager; systemd owns timing.
Singleton {
    id: root

    readonly property string helper:
        Quickshell.env("HOME") + "/.local/bin/quickshell-reminder"
    property var records: []
    property bool loading: false
    property bool refreshPending: false
    property string error: ""
    readonly property int count: records.length
    readonly property double nextDue: count > 0 ? Number(records[0].due) : 0
    readonly property string nextDueLabel: nextDue > 0
        ? Qt.formatDateTime(new Date(nextDue * 1000), Settings.clock24 ? "HH:mm" : "h:mm AP")
        : ""
    readonly property string tooltip: count === 0 ? "Reminders"
        : count + (count === 1 ? " reminder" : " reminders")
            + " · next " + nextDueLabel

    function refresh() {
        if (listProc.running) {
            refreshPending = true;
            return;
        }
        loading = true;
        listProc.running = true;
    }

    function restore() {
        if (!restoreProc.running)
            restoreProc.running = true;
    }

    function run(args) {
        Quickshell.execDetached([helper].concat(args));
        settle.restart();
    }

    function add(minutes, message) {
        run(["add", String(minutes), message || ""]);
    }

    function cancel(id) {
        run(["cancel", id]);
    }

    function clear() {
        run(["clear"]);
    }

    Process {
        id: listProc
        command: [root.helper, "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    root.records = Array.isArray(parsed) ? parsed : [];
                    root.error = "";
                } catch (e) {
                    root.error = "Could not read reminders";
                }
            }
        }
        onExited: exitCode => {
            root.loading = false;
            if (exitCode !== 0)
                root.error = "Could not read reminders";
            if (root.refreshPending) {
                root.refreshPending = false;
                Qt.callLater(root.refresh);
            }
        }
    }

    Process {
        id: restoreProc
        command: [root.helper, "restore"]
        onExited: root.refresh()
    }

    Timer {
        id: settle
        interval: 300
        repeat: true
        property int ticks: 0
        onTriggered: {
            root.refresh();
            if (++ticks >= 12)
                stop();
        }
        onRunningChanged: {
            if (running)
                ticks = 0;
        }
    }

    // Refresh is the normal fallback for a missed IPC call. Restore also
    // retries overdue records whose notification delivery previously failed.
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.restore()
    }

    Component.onCompleted: restore()
}
