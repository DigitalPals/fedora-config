pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Wallpaper management (took over from Lumen): quickshell draws the image
// on the background layer; this singleton tracks the directory, the
// current selection, and persists it across sessions.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    readonly property string stateFile: Quickshell.statePath("wallpaper")
    property var files: []
    property string current: ""

    function set(path) {
        current = path;
        persistProc.running = false;
        persistProc.running = true;
    }

    function shuffle() {
        if (files.length < 2)
            return;
        const others = files.filter(f => f !== current);
        set(others[Math.floor(Math.random() * others.length)]);
    }

    Process {
        id: listProc
        command: ["bash", "-c", "ls -1 \"" + root.dir + "\" 2>/dev/null | grep -iE '\\.(jpg|jpeg|png|webp)$'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.files = text.trim() === "" ? [] : text.trim().split("\n").map(f => root.dir + "/" + f);
            }
        }
    }

    Process {
        id: persistProc
        command: ["bash", "-c", "printf '%s' \"" + root.current + "\" > \"" + root.stateFile + "\""]
    }

    FileView {
        id: stateView
        path: root.stateFile
        onLoaded: {
            const saved = text().trim();
            if (saved !== "")
                root.current = saved;
        }
        onLoadFailed: {
            // First run: fall back to the wallpaper Lumen had configured.
            root.current = root.dir + "/snowy-mountain-lake-purple-sunset-fk.jpg";
        }
    }
}
