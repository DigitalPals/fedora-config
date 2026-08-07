pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "SettingsHelpers.js" as SettingsHelpers

// Shell settings store (design v2, "Shell settings"). Single source of truth
// for user-tunable shell configuration: merged over defaults on load,
// debounce-saved, and watched so external edits of the JSON apply live.
//
// The path is a fixed literal rather than Quickshell.statePath(): statePath
// resolves under by-shell/<config-hash>/, so a dev run from a different
// config directory would silently fork the settings. The settings UI also
// displays this exact path.
//
// Dependency rule: Theme binds to Settings, never the reverse. Keeping the
// direction one-way is what makes the live-apply bindings loop-free.
Singleton {
    id: root

    readonly property string filePath:
        Quickshell.env("HOME") + "/.local/state/quickshell/shell-settings.json"

    readonly property var defaults: SettingsHelpers.defaults()
    readonly property var fontChoices: SettingsHelpers.FONT_CHOICES

    // ---- Persisted settings ----------------------------------------------
    property string wall: defaults.wall
    property string wallDir: defaults.wallDir
    property string shuffle: defaults.shuffle
    property int barHeight: defaults.barHeight
    property int barRadius: defaults.barRadius
    property string font: defaults.font
    property string accent: defaults.accent
    property bool accentWall: defaults.accentWall
    property string position: defaults.position
    property bool floating: defaults.floating
    property int gap: defaults.gap
    property bool autoHide: defaults.autoHide
    property bool exclusive: defaults.exclusive
    property string monitor: defaults.monitor
    property bool clock24: defaults.clock24
    property string unit: defaults.unit
    property int warmth: defaults.warmth
    property string osd: defaults.osd
    property int pollMax: defaults.pollMax
    property real scrollFactor: defaults.scrollFactor
    property bool notifDnd: defaults.notifDnd
    property string notifQuiet: defaults.notifQuiet
    property int notifQuietStart: defaults.notifQuietStart
    property int notifQuietEnd: defaults.notifQuietEnd
    property int notifDuration: defaults.notifDuration
    property string notifPosition: defaults.notifPosition
    property string notifDensity: defaults.notifDensity
    property bool notifIcons: defaults.notifIcons
    property bool notifProgress: defaults.notifProgress
    property int notifBodyLines: defaults.notifBodyLines
    property var mods: defaults.mods
    // Wallpaper-accent extraction cache: the derived color and the wallpaper
    // it was derived from, persisted so magick never re-runs across restarts.
    property string wallAccent: defaults.wallAccent
    property string wallAccentFor: defaults.wallAccentFor

    // ---- Runtime state (not persisted) -----------------------------------
    property bool panelOpen: false
    property string page: "appearance"
    property bool loaded: false
    property bool firstRun: false
    property bool savePending: false
    property bool saveError: false
    property double lastSavedAt: 0
    property var resetSnapshot: null
    property string resetLabel: ""
    property string announcement: ""
    property bool migrationPending: false
    readonly property bool undoAvailable: resetSnapshot !== null

    // Guards saves while loaded values are being applied.
    property bool ready: false

    readonly property string effectiveAccent:
        accentWall && wallAccent !== "" ? wallAccent : accent
    readonly property bool modsModified:
        JSON.stringify(mods) !== JSON.stringify(defaults.mods)

    readonly property var validPages: ["appearance", "wallpaper", "bar", "modules", "notifications", "system"]

    // One dirty/reset key list per settings page (grouped-rail design 1c).
    readonly property var sectionKeys: ({
        wallpaper: ["wall", "wallDir", "shuffle"],
        appearance: ["barHeight", "barRadius", "font", "accent", "accentWall"],
        bar: ["position", "floating", "gap", "autoHide", "exclusive", "monitor"],
        modules: ["mods"],
        notifications: ["notifDnd", "notifQuiet", "notifQuietStart", "notifQuietEnd",
            "notifDuration", "notifPosition", "notifDensity", "notifIcons",
            "notifProgress", "notifBodyLines"],
        system: ["clock24", "unit", "warmth", "osd", "pollMax", "scrollFactor"]
    })

    // ---- Connected-popout lifecycle -------------------------------------
    function showPanel(targetPage) {
        if (targetPage && validPages.indexOf(targetPage) !== -1)
            page = targetPage;
        // Never inherit Control Center's right-side module anchor.
        Popouts.openPanel("settings", "center", Qt.rect(0, 0, 0, 0));
        panelOpen = true;
    }

    function togglePanel(targetPage) {
        if (panelOpen && Popouts.open && Popouts.currentName === "settings")
            closePanel();
        else
            showPanel(targetPage);
    }

    function closePanel() {
        if (Popouts.currentName === "settings")
            Popouts.close();
        panelOpen = false;
    }

    function sectionDirty(section) {
        return (sectionKeys[section] || []).some(key =>
            JSON.stringify(root[key]) !== JSON.stringify(defaults[key]));
    }

    // ---- Writers ---------------------------------------------------------
    function clearUndo() {
        resetTimer.stop();
        resetSnapshot = null;
        resetLabel = "";
    }

    function set(key, value) {
        clearUndo();
        migrationPending = false;
        root[key] = value;
    }

    function setInternal(key, value) {
        root[key] = value;
    }

    function setModuleEnabled(id, on) {
        clearUndo();
        migrationPending = false;
        const next = { left: [], center: [], right: [] };
        for (const col of ["left", "center", "right"])
            next[col] = mods[col].map(m => m.id === id
                ? ({ id: m.id, on: on, detail: m.detail }) : m);
        mods = next;
    }

    function setModuleDetail(id, detail) {
        clearUndo();
        migrationPending = false;
        const next = { left: [], center: [], right: [] };
        for (const col of ["left", "center", "right"])
            next[col] = mods[col].map(m => m.id === id
                ? ({ id: m.id, on: m.on, detail: SettingsHelpers.detailIn(detail) }) : m);
        mods = next;
    }

    function setModuleOrder(left, center, right) {
        clearUndo();
        migrationPending = false;
        mods = SettingsHelpers.normalizeMods({ left: left, center: center, right: right });
    }

    function resetKeys(keys, label) {
        migrationPending = false;
        const previous = {};
        for (const key of keys)
            previous[key] = SettingsHelpers.clone(root[key]);
        resetSnapshot = previous;
        resetLabel = label || (keys.length === 1 ? "Setting" : "Settings");
        for (const key of keys)
            root[key] = key === "mods" ? SettingsHelpers.defaultMods() : defaults[key];
        announcement = resetLabel + " reset. Undo available for eight seconds.";
        resetTimer.restart();
    }

    function resetSection(section) {
        const labels = {
            wallpaper: "Wallpaper", appearance: "Appearance", bar: "Bar layout",
            modules: "Modules", notifications: "Notifications", system: "System"
        };
        resetKeys(sectionKeys[section] || [], labels[section] || "Settings");
    }

    function resetAll() {
        resetKeys(Object.keys(defaults).filter(key => key !== "wallAccent" && key !== "wallAccentFor"),
            "All settings");
    }

    function undoReset() {
        if (!resetSnapshot)
            return;
        const previous = resetSnapshot;
        resetTimer.stop();
        for (const key of Object.keys(previous))
            root[key] = SettingsHelpers.clone(previous[key]);
        resetSnapshot = null;
        const label = resetLabel;
        resetLabel = "";
        announcement = label + " restored.";
    }

    function retrySave() {
        savePending = true;
        saveNow();
    }

    // ---- Persistence -----------------------------------------------------
    function snapshot() {
        return {
            wall: wall, wallDir: wallDir, shuffle: shuffle,
            barHeight: barHeight, barRadius: barRadius,
            font: font, accent: accent, accentWall: accentWall, position: position,
            floating: floating, gap: gap, autoHide: autoHide, exclusive: exclusive,
            monitor: monitor, clock24: clock24, unit: unit, warmth: warmth,
            osd: osd, pollMax: pollMax, scrollFactor: scrollFactor,
            notifDnd: notifDnd, notifQuiet: notifQuiet,
            notifQuietStart: notifQuietStart, notifQuietEnd: notifQuietEnd,
            notifDuration: notifDuration, notifPosition: notifPosition,
            notifDensity: notifDensity, notifIcons: notifIcons,
            notifProgress: notifProgress, notifBodyLines: notifBodyLines,
            mods: mods, wallAccent: wallAccent, wallAccentFor: wallAccentFor
        };
    }

    function applyLoaded(rawText) {
        const parsed = SettingsHelpers.parse(rawText);
        const merged = SettingsHelpers.merge(parsed);
        // Skip echoes of our own atomic writes (watchChanges reports them)
        // and external edits that merge back to the current state.
        if (loaded && SettingsHelpers.serialize(merged) === SettingsHelpers.serialize(snapshot()))
            return;
        ready = false;
        saveTimer.stop();
        savePending = false;
        clearUndo();
        wall = merged.wall;
        wallDir = merged.wallDir;
        shuffle = merged.shuffle;
        barHeight = merged.barHeight;
        barRadius = merged.barRadius;
        font = merged.font;
        accent = merged.accent;
        accentWall = merged.accentWall;
        position = merged.position;
        floating = merged.floating;
        gap = merged.gap;
        autoHide = merged.autoHide;
        exclusive = merged.exclusive;
        monitor = merged.monitor;
        clock24 = merged.clock24;
        unit = merged.unit;
        warmth = merged.warmth;
        osd = merged.osd;
        pollMax = merged.pollMax;
        scrollFactor = merged.scrollFactor;
        notifDnd = merged.notifDnd;
        notifQuiet = merged.notifQuiet;
        notifQuietStart = merged.notifQuietStart;
        notifQuietEnd = merged.notifQuietEnd;
        notifDuration = merged.notifDuration;
        notifPosition = merged.notifPosition;
        notifDensity = merged.notifDensity;
        notifIcons = merged.notifIcons;
        notifProgress = merged.notifProgress;
        notifBodyLines = merged.notifBodyLines;
        mods = merged.mods;
        wallAccent = merged.wallAccent;
        wallAccentFor = merged.wallAccentFor;
        ready = true;
        migrationPending = parsed !== null && parsed.v !== 3;
        firstRun = parsed === null;
        loaded = true;
        applyScrollFactor();
    }

    function saveNow() {
        if (!ready)
            return;
        const retrying = saveError;
        saveError = false;
        try {
            store.setText(SettingsHelpers.serialize(snapshot()));
            savePending = false;
            lastSavedAt = Date.now();
            if (retrying)
                announcement = "Settings saved.";
        } catch (error) {
            savePending = false;
            saveError = true;
            announcement = "Could not save settings. Retry is available.";
            console.warn("settings save failed:", error);
        }
    }

    function scheduleSave() {
        if (!ready || migrationPending)
            return;
        savePending = true;
        saveTimer.restart();
    }

    onWallChanged: scheduleSave()
    onWallDirChanged: scheduleSave()
    onShuffleChanged: scheduleSave()
    onBarHeightChanged: scheduleSave()
    onBarRadiusChanged: scheduleSave()
    onFontChanged: scheduleSave()
    onAccentChanged: scheduleSave()
    onAccentWallChanged: scheduleSave()
    onPositionChanged: scheduleSave()
    onFloatingChanged: scheduleSave()
    onGapChanged: scheduleSave()
    onAutoHideChanged: scheduleSave()
    onExclusiveChanged: scheduleSave()
    onMonitorChanged: scheduleSave()
    onClock24Changed: scheduleSave()
    onUnitChanged: scheduleSave()
    onWarmthChanged: scheduleSave()
    onOsdChanged: scheduleSave()
    onPollMaxChanged: scheduleSave()
    onScrollFactorChanged: {
        scheduleSave();
        applyScrollFactor();
    }
    onNotifDndChanged: scheduleSave()
    onNotifQuietChanged: scheduleSave()
    onNotifQuietStartChanged: scheduleSave()
    onNotifQuietEndChanged: scheduleSave()
    onNotifDurationChanged: scheduleSave()
    onNotifPositionChanged: scheduleSave()
    onNotifDensityChanged: scheduleSave()
    onNotifIconsChanged: scheduleSave()
    onNotifProgressChanged: scheduleSave()
    onNotifBodyLinesChanged: scheduleSave()
    onModsChanged: scheduleSave()
    onWallAccentChanged: scheduleSave()
    onWallAccentForChanged: scheduleSave()

    Timer {
        id: saveTimer
        interval: 400
        onTriggered: root.saveNow()
    }

    Timer {
        id: resetTimer
        interval: 8000
        onTriggered: root.clearUndo()
    }

    // Debounce pointer motion from the slider, then apply the final value to
    // Hyprland immediately. input.lua reads the same persisted setting so a
    // compositor reload or reboot retains it.
    property real dispatchedScrollFactor: -1

    function applyScrollFactor() {
        if (loaded)
            scrollApplyTimer.restart();
    }

    Timer {
        id: scrollApplyTimer
        interval: 75
        onTriggered: {
            if (scrollFactorProc.running)
                return;
            root.dispatchedScrollFactor = root.scrollFactor;
            scrollFactorProc.command = ["hyprctl", "keyword",
                "input:touchpad:scroll_factor", root.scrollFactor.toFixed(1)];
            scrollFactorProc.running = true;
        }
    }

    Process {
        id: scrollFactorProc

        onExited: exitCode => {
            if (exitCode !== 0)
                console.warn("could not apply touchpad scroll speed:", exitCode);
            if (Math.abs(root.dispatchedScrollFactor - root.scrollFactor) > 0.001)
                scrollApplyTimer.restart();
        }
    }

    FileView {
        id: store
        path: root.filePath
        printErrors: false
        atomicWrites: true
        blockWrites: true
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyLoaded(text())
        onLoadFailed: root.applyLoaded("")
    }

    Connections {
        target: Popouts

        function onChanged() {
            root.panelOpen = Popouts.open && Popouts.currentName === "settings";
        }
    }

    // Force the load to complete during singleton construction so the first
    // Theme/Bar bindings never see one frame of defaults.
    Component.onCompleted: {
        if (!loaded)
            applyLoaded(store.text());
    }
}
