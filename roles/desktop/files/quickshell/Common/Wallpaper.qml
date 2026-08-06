pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

// Wallpaper management: quickshell draws the image on the background layer;
// this singleton tracks the directory and delegates the current selection to
// the Settings store (design v2 Wallpaper page). It also derives the
// from-wallpaper accent: dominant hue sampled by ImageMagick, pastelized to
// the palette's lightness so accent foregrounds keep their contrast, cached
// in Settings so magick never re-runs for an unchanged wallpaper.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    property var files: []
    readonly property bool loading: folderModel.status === FolderListModel.Loading
    property bool accentBusy: false
    property string accentError: ""
    property string queuedAccentFor: ""
    property string activeAccentFor: ""

    readonly property string current:
        Settings.wall !== "" ? url(dir + "/" + Settings.wall) : ""

    function url(path) {
        return path.startsWith("file:") ? path : "file://" + path;
    }

    function set(path) {
        Settings.set("wall", path.split("/").pop());
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

    // Pre-settings state file, now read-only: migrated into Settings.wall on
    // the store's first run and never written again.
    FileView {
        id: legacyState
        path: Quickshell.statePath("wallpaper")
        printErrors: false
        onLoaded: {
            const saved = text().trim();
            if (Settings.firstRun && saved !== "")
                Settings.set("wall", saved.split("/").pop());
        }
    }

    // ---- rotate wallpaper -------------------------------------------------
    readonly property int shuffleMs: Settings.shuffle === "15m" ? 900000
        : Settings.shuffle === "1h" ? 3600000 : 86400000

    Timer {
        running: Settings.shuffle !== "Off"
        repeat: true
        interval: root.shuffleMs
        onTriggered: root.shuffle()
    }

    // ---- from-wallpaper accent -------------------------------------------
    function extractAccent() {
        if (!Settings.accentWall) {
            queuedAccentFor = "";
            return;
        }
        if (Settings.wall === "" || Settings.wallAccentFor === Settings.wall)
            return;
        // Queue by immutable wallpaper identity. A late ImageMagick result
        // must never be attributed to whichever image is current at exit.
        queuedAccentFor = Settings.wall;
        startQueuedAccent();
    }

    function startQueuedAccent() {
        if (accentProc.running || queuedAccentFor === "" || !Settings.accentWall)
            return;
        activeAccentFor = queuedAccentFor;
        queuedAccentFor = "";
        accentError = "";
        accentBusy = true;
        accentProc.command = ["magick", dir + "/" + activeAccentFor,
            "-resize", "1x1!", "-format", "%[hex:u.p{0,0}]", "info:"];
        accentProc.running = true;
    }

    // Average color → hue only; saturation/lightness are pinned to the
    // built-in palette's pastel band (#9ecbeb ≈ S.53 L.77) so any wallpaper
    // yields an AA-safe accent and accentFg stays legible on accent fills.
    function pastelize(hexText) {
        const match = hexText.match(/[0-9a-fA-F]{6}/);
        if (!match)
            return "";
        const r = parseInt(match[0].slice(0, 2), 16) / 255;
        const g = parseInt(match[0].slice(2, 4), 16) / 255;
        const b = parseInt(match[0].slice(4, 6), 16) / 255;
        const max = Math.max(r, g, b);
        const min = Math.min(r, g, b);
        let h = 0;
        if (max !== min) {
            const d = max - min;
            if (max === r)
                h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
            else if (max === g)
                h = ((b - r) / d + 2) / 6;
            else
                h = ((r - g) / d + 4) / 6;
        }
        return String(Qt.hsla(h, 0.5, 0.75, 1));
    }

    Process {
        id: accentProc

        stdout: StdioCollector {
            id: accentOut
        }

        onExited: exitCode => {
            const completedFor = root.activeAccentFor;
            root.activeAccentFor = "";
            if (exitCode !== 0) {
                root.accentError = "Could not extract a color";
                console.warn("wallpaper accent extraction failed:", exitCode);
            } else {
                const pastel = root.pastelize(accentOut.text);
                if (pastel !== "" && Settings.accentWall
                        && Settings.wall === completedFor) {
                    Settings.set("wallAccent", pastel);
                    Settings.set("wallAccentFor", completedFor);
                } else if (pastel === "") {
                    root.accentError = "No usable color found";
                }
            }
            if (root.accentError !== "")
                console.warn("wallpaper accent extraction returned no color:", accentOut.text);
            root.accentBusy = false;
            if (root.queuedAccentFor !== "")
                Qt.callLater(root.startQueuedAccent);
        }
    }

    Connections {
        target: Settings

        function onWallChanged() {
            root.extractAccent();
        }

        function onAccentWallChanged() {
            root.extractAccent();
        }
    }

    // Covers accentWall persisted on with a stale or missing cache.
    Component.onCompleted: extractAccent()
}
