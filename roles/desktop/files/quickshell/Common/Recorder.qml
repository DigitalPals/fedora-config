pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Screen-recording state, read from the state files ~/.local/bin/screen-record
// keeps in $XDG_RUNTIME_DIR.
//
// The shell deliberately does not drive wf-recorder itself: the script already
// owns region selection, the freeze overlay, the output path and the saved
// notification, and it is bound to a compositor key, so a recording can start
// without the shell involved at all. Watching its state is what keeps the bar
// chip honest either way.
Singleton {
    id: root

    readonly property string stateDir:
        (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/screen-record"
    readonly property string script:
        Quickshell.env("HOME") + "/.local/bin/screen-record"

    property bool active: false
    property int recorderPid: 0
    property string outputFile: ""
    // Epoch seconds. 0 while not recording, or while a recording started by an
    // older copy of the script left no stamp behind.
    property double startedAt: 0
    // Seconds since the recording began, ticking once a second while active.
    property int elapsed: 0

    readonly property string elapsedLabel: {
        const total = Math.max(0, elapsed);
        const minutes = Math.floor(total / 60);
        const seconds = Math.floor(total % 60);
        return minutes + ":" + String(seconds).padStart(2, "0");
    }

    function toggle() {
        Quickshell.execDetached(["sh", "-c", root.script]);
        // The script selects a region before it writes any state, so give the
        // user time to drag one out before looking again.
        settle.restart();
    }

    function refresh() {
        pidView.reload();
        stampView.reload();
        outputView.reload();
    }

    function recomputeElapsed() {
        if (!active) {
            elapsed = 0;
            return;
        }
        elapsed = startedAt > 0
            ? Math.max(0, Math.floor(Date.now() / 1000 - startedAt))
            : elapsed + 1;
    }

    // Cheap: three small reads off tmpfs, no process spawned. The chip has to
    // notice a recording the compositor keybind started, and there is no
    // signal for that beyond the file appearing.
    Timer {
        id: poll
        interval: 4000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        id: settle
        interval: 1200
        repeat: true
        triggeredOnStart: false
        property int ticks: 0
        onTriggered: {
            root.refresh();
            if (++ticks > 25) {
                ticks = 0;
                stop();
            }
        }
        onRunningChanged: {
            if (running)
                ticks = 0;
        }
    }

    Timer {
        interval: 1000
        running: root.active
        repeat: true
        onTriggered: root.recomputeElapsed()
    }

    onActiveChanged: recomputeElapsed()

    FileView {
        id: pidView
        path: root.stateDir + "/wf-recorder.pid"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const value = Number(text().trim());
            root.recorderPid = Number.isInteger(value) && value > 0 ? value : 0;
            if (root.recorderPid > 0)
                procView.reload();
            else
                root.active = false;
        }
        onLoadFailed: {
            root.recorderPid = 0;
            root.active = false;
            root.startedAt = 0;
        }
    }

    // A PID file is only a ready marker, not proof the child is still alive.
    // wf-recorder can fail after the launching script exits; checking procfs on
    // the existing four-second poll prevents a stale file pinning the red chip
    // on screen forever, without spawning another process to do it.
    FileView {
        id: procView
        path: root.recorderPid > 0 ? "/proc/" + root.recorderPid + "/comm" : ""
        printErrors: false
        onLoaded: root.active = text().trim() === "wf-recorder"
        onLoadFailed: root.active = false
    }

    FileView {
        id: stampView
        path: root.stateDir + "/started-at"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const value = Number(text().trim());
            root.startedAt = isFinite(value) && value > 0 ? value : 0;
            root.recomputeElapsed();
        }
        onLoadFailed: root.startedAt = 0
    }

    FileView {
        id: outputView
        path: root.stateDir + "/output-file"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.outputFile = text().trim()
        onLoadFailed: root.outputFile = ""
    }
}
