pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Format.js" as Format

// Launcher lifecycle and persistent application-use ranking. The selected
// screen is captured when opening so the overlay does not jump mid-search.
Singleton {
    id: root

    property bool open: false
    property var screen: null
    property var usage: ({})
    property string commandError: ""
    property string pendingCommand: ""

    readonly property string usageFile: Quickshell.statePath("launcher-usage.json")

    function toggle() {
        if (open) {
            close();
            return;
        }
        Popouts.close();
        screen = Screens.focused;
        open = true;
    }

    function close() {
        open = false;
    }

    function recordLaunch(app) {
        const key = app.id || app.name;
        const previous = usage[key] || { count: 0, last: 0 };
        const next = Object.assign({}, usage);
        next[key] = { count: previous.count + 1, last: Date.now() };
        usage = next;
        usageView.setText(JSON.stringify(usage));
    }

    function usageBoost(app) {
        const item = usage[app.id || app.name];
        if (!item)
            return 0;
        const ageDays = Math.max(0, Date.now() - item.last) / Format.MS_DAY;
        return Math.log(1 + item.count) * 180 + 700 / (1 + ageDays);
    }

    function executeCommand(command) {
        pendingCommand = command;
        commandError = "";
        commandProc.running = false;
        commandProc.command = ["sh", "-c", command];
        commandProc.running = true;
        close();
    }

    FileView {
        id: usageView
        path: root.usageFile
        printErrors: false
        atomicWrites: true
        blockWrites: true
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (parsed && typeof parsed === "object")
                    root.usage = parsed;
            } catch (e) {
                console.warn("launcher usage state is invalid:", e);
            }
        }
    }

    Process {
        id: commandProc
        stderr: StdioCollector {
            onStreamFinished: root.commandError = text.trim()
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                const detail = root.commandError || `Command exited with status ${exitCode}`;
                Quickshell.execDetached(["notify-send", "Launcher command failed", detail]);
            }
        }
    }
}
