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

    // Guards saves while loaded values are being applied.
    property bool ready: false

    readonly property string effectiveAccent:
        accentWall && wallAccent !== "" ? wallAccent : accent
    readonly property bool modsModified:
        JSON.stringify(mods) !== JSON.stringify(defaults.mods)

    readonly property var validPages: ["appearance", "wallpaper", "bar", "modules", "system"]

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
        const map = {
            wallpaper: ["wall", "shuffle"],
            appearance: ["barHeight", "barRadius", "font", "accent", "accentWall"],
            bar: ["position", "floating", "gap", "autoHide", "exclusive", "monitor"],
            modules: ["mods"],
            system: ["clock24", "unit", "warmth", "osd", "pollMax"]
        };
        return (map[section] || []).some(key =>
            JSON.stringify(root[key]) !== JSON.stringify(defaults[key]));
    }

    // ---- Writers ---------------------------------------------------------
    function set(key, value) {
        root[key] = value;
    }

    function setModuleEnabled(id, on) {
        const next = { left: [], center: [], right: [] };
        for (const col of ["left", "center", "right"])
            next[col] = mods[col].map(m => m.id === id ? ({ id: m.id, on: on }) : m);
        mods = next;
    }

    function setModuleOrder(left, center, right) {
        mods = SettingsHelpers.normalizeMods({ left: left, center: center, right: right });
    }

    function resetKeys(keys) {
        for (const key of keys)
            root[key] = key === "mods" ? SettingsHelpers.defaultMods() : defaults[key];
    }

    function resetSection(section) {
        const map = {
            wallpaper: ["wall", "shuffle"],
            appearance: ["barHeight", "barRadius", "font", "accent", "accentWall"],
            bar: ["position", "floating", "gap", "autoHide", "exclusive", "monitor"],
            modules: ["mods"],
            system: ["clock24", "unit", "warmth", "osd", "pollMax"]
        };
        resetKeys(map[section] || []);
    }

    function resetAll() {
        resetKeys(Object.keys(defaults).filter(key => key !== "wallAccent" && key !== "wallAccentFor"));
    }

    // ---- Persistence -----------------------------------------------------
    function snapshot() {
        return {
            wall: wall, shuffle: shuffle, barHeight: barHeight, barRadius: barRadius,
            font: font, accent: accent, accentWall: accentWall, position: position,
            floating: floating, gap: gap, autoHide: autoHide, exclusive: exclusive,
            monitor: monitor, clock24: clock24, unit: unit, warmth: warmth,
            osd: osd, pollMax: pollMax, mods: mods,
            wallAccent: wallAccent, wallAccentFor: wallAccentFor
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
        wall = merged.wall;
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
        mods = merged.mods;
        wallAccent = merged.wallAccent;
        wallAccentFor = merged.wallAccentFor;
        ready = true;
        firstRun = parsed === null;
        loaded = true;
    }

    function saveNow() {
        if (!ready)
            return;
        saveError = false;
        try {
            store.setText(SettingsHelpers.serialize(snapshot()));
            savePending = false;
            lastSavedAt = Date.now();
        } catch (error) {
            savePending = false;
            saveError = true;
            console.warn("settings save failed:", error);
        }
    }

    function scheduleSave() {
        if (!ready)
            return;
        savePending = true;
        saveTimer.restart();
    }

    onWallChanged: scheduleSave()
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
    onModsChanged: scheduleSave()
    onWallAccentChanged: scheduleSave()
    onWallAccentForChanged: scheduleSave()

    Timer {
        id: saveTimer
        interval: 400
        onTriggered: root.saveNow()
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
