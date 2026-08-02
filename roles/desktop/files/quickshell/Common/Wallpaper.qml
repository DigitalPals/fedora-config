pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

// Wallpaper management: quickshell draws the image
// on the background layer; this singleton tracks the directory, the
// current selection, and persists it across sessions.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    readonly property string stateFile: Quickshell.statePath("wallpaper")
    property var files: []
    property string current: ""

    function url(path) {
        return path.startsWith("file:") ? path : "file://" + path;
    }

    function set(path) {
        current = path;
        stateView.setText(current);
    }

    function shuffle() {
        if (files.length < 2)
            return;
        const others = files.filter(f => f !== current);
        set(others[Math.floor(Math.random() * others.length)]);
    }

    function refreshFiles() {
        const next = [];
        for (let i = 0; i < folderModel.count; i++) {
            const url = folderModel.get(i, "fileUrl");
            if (url)
                next.push(url.toString());
        }
        files = next;
    }

    FolderListModel {
        id: folderModel
        folder: "file://" + root.dir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.JPG", "*.JPEG", "*.PNG", "*.WEBP"]
        showDirs: false
        showFiles: true
        sortField: FolderListModel.Name
        onCountChanged: root.refreshFiles()
        onStatusChanged: root.refreshFiles()
    }

    FileView {
        id: stateView
        path: root.stateFile
        printErrors: false
        atomicWrites: true
        blockWrites: true
        onLoaded: {
            const saved = text().trim();
            if (saved !== "")
                root.current = root.url(saved);
        }
        onLoadFailed: {
            // First run: fall back to the previously configured wallpaper.
            root.current = root.url(root.dir + "/snow-capped-mountains-with-full-moon-lo.jpg");
        }
    }
}
