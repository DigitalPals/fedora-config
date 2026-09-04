pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Voxtype writes this state for every control path, including compositor
// keybindings. Watching it keeps the menubar honest even when it did not start
// the recording itself.
Singleton {
    id: root

    readonly property string statePath:
        (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/voxtype/state"
    property string state: "idle"
    readonly property bool recording: state === "recording"
    readonly property bool transcribing: state === "transcribing"
    readonly property bool busy: recording || transcribing

    function refresh() {
        stateView.reload();
    }

    function run(command) {
        Quickshell.execDetached(command);
        settle.restart();
    }

    function toggle(language) {
        if (recording)
            run(["voxtype", "record", "stop"]);
        else if (transcribing)
            run(["voxtype", "record", "cancel"]);
        else {
            const selected = language || Settings.modOpts.indicators.dictationPrimaryLanguage;
            if (selected === "off")
                return;
            run(["voxtype", "--model", Settings.modOpts.indicators.dictationModel,
                "--language", selected, "record", "start"]);
        }
    }

    FileView {
        id: stateView
        path: root.statePath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const value = text().trim();
            root.state = ["idle", "recording", "transcribing"].indexOf(value) !== -1
                ? value : "idle";
        }
        onLoadFailed: root.state = "idle"
    }

    // inotify covers normal transitions; this bounded replay covers a daemon
    // replacing the state file between watches after a bar-originated action.
    Timer {
        id: settle
        interval: 250
        repeat: true
        property int ticks: 0
        onTriggered: {
            root.refresh();
            if (++ticks >= 20)
                stop();
        }
        onRunningChanged: {
            if (running)
                ticks = 0;
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
