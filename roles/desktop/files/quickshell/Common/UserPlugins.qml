pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Separate from Settings: older shell schemas must never rewrite plugin data.
Singleton {
    id: root

    property var plugins: []
    property string error: ""
    property string lastResult: ""
    property var pendingWrites: []
    readonly property var enabled: plugins.filter(plugin => plugin.enabled)
    readonly property string helper: Quickshell.shellDir + "/scripts/user-plugins.py"

    function refresh() {
        if (!scanner.running)
            scanner.running = true;
    }

    function setSetting(id, key, value) {
        pendingWrites = pendingWrites.concat([["python3", helper, "set", id, key, value]]);
        nextWrite();
    }

    function nextWrite() {
        if (writer.running || pendingWrites.length === 0)
            return;
        writer.command = pendingWrites[0];
        pendingWrites = pendingWrites.slice(1);
        writer.running = true;
    }

    Process {
        id: scanner
        command: ["python3", root.helper, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text === root.lastResult)
                    return;
                try {
                    const result = JSON.parse(text);
                    root.error = result.error;
                    // A malformed registry is shown, never repaired with defaults.
                    root.plugins = result.plugins;
                    root.lastResult = text;
                } catch (exception) {
                    root.error = "Could not read user widgets";
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0)
                root.error = "Could not inspect user widgets";
        }
    }

    Process {
        id: writer
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    root.error = text.trim();
            }
        }
        onExited: (code, status) => {
            root.refresh();
            Qt.callLater(root.nextWrite);
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
