pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "NetworkStatusHelpers.js" as NetworkStatusHelpers
import "ProcHelpers.js" as ProcHelpers

// One event-driven answer to "can Internet work start now?" for every shell
// service. A device being present is not enough: loopback, Docker, or a Wi-Fi
// association can all exist before DNS and a default route do. NetworkManager's
// overall state reaches connected only once it has global connectivity.
//
// `nmcli monitor` supplies the edge; the small status command supplies both
// the initial value and a stable, machine-readable snapshot after each edge.
// The poll is only a safety net if the monitor is interrupted.
Singleton {
    id: root

    property bool known: false
    property bool online: false
    property string error: ""
    property bool refreshAgain: false
    property string lastLoggedError: ""

    function refresh() {
        if (statusProc.running) {
            refreshAgain = true;
            return;
        }
        statusProc.running = true;
    }

    function apply(exitCode, body, errText) {
        const next = exitCode === 0 ? NetworkStatusHelpers.onlineState(body) : null;
        if (next !== null) {
            known = true;
            online = next;
            error = "";
            return;
        }

        // A failed or unreadable snapshot cannot vouch for the old state.
        known = false;
        online = false;
        error = exitCode === 0
            ? "NetworkManager returned an unknown connectivity state"
            : ProcHelpers.commandError("NetworkManager status", exitCode, errText,
                ({ 124: "NetworkManager status timed out" }));
        if (error !== lastLoggedError) {
            console.warn("network status unavailable:", error);
            lastLoggedError = error;
        }
    }

    onErrorChanged: {
        if (error === "")
            lastLoggedError = "";
    }

    Timer {
        id: snapshotDebounce
        interval: 250
        onTriggered: root.refresh()
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: monitorRestart
        interval: 5000
        onTriggered: {
            if (!monitorProc.running)
                monitorProc.running = true;
        }
    }

    Process {
        id: statusProc

        property string body: ""
        property string errText: ""
        property bool exitSeen: false
        property int lastExit: 0

        command: ["timeout", "5s", "env", "LC_ALL=C", "nmcli", "--terse",
            "--fields", "STATE", "general", "status"]

        stdout: StdioCollector {
            onStreamFinished: statusProc.body = text
        }
        stderr: StdioCollector {
            onStreamFinished: statusProc.errText = text
        }
        onExited: (exitCode, exitStatus) => {
            statusProc.exitSeen = true;
            statusProc.lastExit = exitCode;
        }
        onRunningChanged: {
            if (running) {
                body = "";
                errText = "";
                exitSeen = false;
                lastExit = 0;
                return;
            }
            root.apply(exitSeen ? lastExit : ProcHelpers.NOT_STARTED, body, errText);
            if (root.refreshAgain) {
                root.refreshAgain = false;
                Qt.callLater(root.refresh);
            }
        }
    }

    Process {
        id: monitorProc

        command: ["env", "LC_ALL=C", "nmcli", "monitor"]
        running: true

        stdout: SplitParser {
            onRead: line => snapshotDebounce.restart()
        }
        onRunningChanged: {
            if (running) {
                monitorRestart.stop();
                return;
            }
            // NetworkManager itself can restart. Keep the fallback snapshot
            // current while waiting to reattach to its event stream.
            root.refresh();
            monitorRestart.restart();
        }
    }

    Component.onCompleted: refresh()
}
