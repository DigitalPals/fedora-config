pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import "SettingsHelpers.js" as SettingsHelpers
import "Format.js" as Format

// Wallpaper management: quickshell draws the image on the background layer;
// this singleton tracks the directory and delegates the current selection to
// the Settings store (design v2 Wallpaper page). It also derives the
// from-wallpaper accent: dominant hue sampled by ImageMagick, pastelized to
// the palette's lightness so accent foregrounds keep their contrast, cached
// in Settings so magick never re-runs for an unchanged wallpaper.
Singleton {
    id: root

    readonly property string dir: Settings.wallDir === "~"
        ? Quickshell.env("HOME")
        : Settings.wallDir.indexOf("~/") === 0
        ? Quickshell.env("HOME") + Settings.wallDir.slice(1) : Settings.wallDir
    property var files: []
    readonly property bool loading: folderModel.status === FolderListModel.Loading
    property bool accentBusy: false
    property string accentError: ""
    property string queuedAccentFor: ""
    property string activeAccentFor: ""
    property string pendingDir: ""
    property bool candidateLoadingSeen: false
    property string directoryError: ""
    property var thumbnailPaths: ({})
    property var thumbnailPending: ({})
    property var thumbnailQueue: []
    property string activeThumbnailSource: ""
    readonly property string currentIdentity: dir + "/" + Settings.wall

    readonly property string current:
        Settings.wall !== "" ? url(dir + "/" + Settings.wall) : ""

    function url(path) {
        return path.startsWith("file:") ? path : "file://" + path;
    }

    function basename(path) {
        const raw = path.split("/").pop();
        try {
            return decodeURIComponent(raw);
        } catch (error) {
            return raw;
        }
    }

    function set(path) {
        Settings.set("wall", basename(path));
    }

    function shuffle() {
        if (files.length < 2)
            return;
        const others = files.filter(f => basename(f) !== Settings.wall);
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

    // The settings grid asks only for its visible delegates. The helper keeps
    // 640x384 JPEG previews on disk and returns a source-revision query so a
    // changed wallpaper bypasses Qt's in-memory pixmap cache. Cached paths stay
    // in this singleton when the Settings page is closed and reopened.
    function thumbnailFor(path) {
        return thumbnailPaths[path] || "";
    }

    function requestThumbnail(path) {
        if (path === "" || thumbnailPending[path])
            return;
        const pending = Object.assign({}, thumbnailPending);
        pending[path] = true;
        thumbnailPending = pending;
        thumbnailQueue = thumbnailQueue.concat([path]);
        startNextThumbnail();
    }

    function startNextThumbnail() {
        if (thumbnailProc.running || activeThumbnailSource !== ""
                || thumbnailQueue.length === 0)
            return;
        activeThumbnailSource = thumbnailQueue[0];
        thumbnailQueue = thumbnailQueue.slice(1);
        thumbnailProc.command = ["python3",
            Quickshell.shellDir + "/scripts/wallpaper-thumbnail.py",
            activeThumbnailSource];
        thumbnailProc.running = true;
    }

    function requestDirectory(path) {
        const normalized = SettingsHelpers.pathIn(path, "");
        if (normalized === "") {
            directoryError = "Choose an absolute folder or a path under ~/";
            return;
        }
        if (normalized === Settings.wallDir) {
            directoryError = "";
            return;
        }
        pendingDir = normalized;
        candidateLoadingSeen = false;
        directoryError = "";
        const expanded = normalized === "~" ? Quickshell.env("HOME")
            : normalized.indexOf("~/") === 0
            ? Quickshell.env("HOME") + normalized.slice(1) : normalized;
        candidateModel.folder = url(expanded);
        candidateTimeout.restart();
        Qt.callLater(validateCandidate);
    }

    function validateCandidate() {
        if (pendingDir === "" || !candidateLoadingSeen
                || candidateModel.status === FolderListModel.Loading)
            return;
        candidateTimeout.stop();
        if (candidateModel.count < 1) {
            directoryError = "Folder is unreadable or has no supported images";
            pendingDir = "";
            return;
        }
        let selected = "";
        for (let i = 0; i < candidateModel.count; i++) {
            const candidate = candidateModel.get(i, "fileName");
            if (candidate === Settings.wall) {
                selected = candidate;
                break;
            }
        }
        if (selected === "")
            selected = candidateModel.get(0, "fileName");
        const committed = pendingDir;
        pendingDir = "";
        Settings.set("wallDir", committed);
        Settings.set("wall", selected);
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

    FolderListModel {
        id: candidateModel
        nameFilters: folderModel.nameFilters
        showDirs: false
        showFiles: true
        sortField: FolderListModel.Name
        onCountChanged: Qt.callLater(root.validateCandidate)
        onStatusChanged: {
            if (status === FolderListModel.Loading)
                root.candidateLoadingSeen = true;
            Qt.callLater(root.validateCandidate);
        }
    }

    Timer {
        id: candidateTimeout
        interval: 2500
        onTriggered: {
            root.directoryError = "Folder could not be read";
            root.pendingDir = "";
        }
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
        : Settings.shuffle === "1h" ? Format.MS_HOUR : Format.MS_DAY

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
        if (Settings.wall === "" || Settings.wallAccentFor === currentIdentity)
            return;
        // Queue by immutable wallpaper identity. A late ImageMagick result
        // must never be attributed to whichever image is current at exit.
        queuedAccentFor = currentIdentity;
        startQueuedAccent();
    }

    function startQueuedAccent() {
        if (accentProc.running || queuedAccentFor === "" || !Settings.accentWall)
            return;
        activeAccentFor = queuedAccentFor;
        queuedAccentFor = "";
        accentError = "";
        accentBusy = true;
        accentProc.command = ["magick", activeAccentFor,
            "-resize", "1x1!", "-format", "%[hex:u.p{0,0}]", "info:"];
        accentProc.running = true;
    }

    // Average color → hue only; saturation/lightness are pinned to the
    // built-in palette's pastel band (#9ecbeb ≈ S.53 L.77) so any wallpaper
    // yields an AA-safe accent and accentFg stays legible on accent fills.
    // The same two helpers drive the accent-hue slider, and they carry the
    // 0.5/0.75 constants this used to restate; hexHue rounds to whole
    // degrees on the way through, which moves a channel by at most 1/255.
    function pastelize(hexText) {
        const match = hexText.match(/[0-9a-fA-F]{6}/);
        if (!match)
            return "";
        return SettingsHelpers.hueToHex(SettingsHelpers.hexHue("#" + match[0], 0));
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
                        && root.currentIdentity === completedFor) {
                    Settings.setInternal("wallAccent", pastel);
                    Settings.setInternal("wallAccentFor", completedFor);
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

    Process {
        id: thumbnailProc

        stdout: StdioCollector {
            id: thumbnailOut
        }

        onExited: exitCode => {
            const completed = root.activeThumbnailSource;
            root.activeThumbnailSource = "";
            const pending = Object.assign({}, root.thumbnailPending);
            delete pending[completed];
            root.thumbnailPending = pending;

            const cached = thumbnailOut.text.trim();
            const paths = Object.assign({}, root.thumbnailPaths);
            if (exitCode === 0 && cached.indexOf("file:") === 0)
                paths[completed] = cached;
            else {
                // Preserve the old behavior if thumbnail generation fails.
                paths[completed] = completed;
                console.warn("wallpaper thumbnail generation failed for", completed);
            }
            root.thumbnailPaths = paths;
            Qt.callLater(root.startNextThumbnail);
        }
    }

    Connections {
        target: Settings

        function onWallChanged() {
            root.extractAccent();
        }

        function onWallDirChanged() {
            root.extractAccent();
        }

        function onAccentWallChanged() {
            root.extractAccent();
        }
    }

    // Covers accentWall persisted on with a stale or missing cache.
    Component.onCompleted: extractAccent()
}
