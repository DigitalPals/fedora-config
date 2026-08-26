// Every popout panel the shell can open, described once.
//
// Four hand-maintained key spaces used to disagree: Popouts' island map, the
// popout host's source map, the `registerPanel()` calls scattered through the
// bar modules, and the module ids in SettingsHelpers. Adding a panel meant
// remembering all four, and the Tailscale popout closing on any settings
// change was exactly what happens when you don't — it is in the first three
// but owned by no module, so the bar's "did my module go away" sweep closed
// it. panel-registry.test.cjs now fails when the maps drift apart.
//
// Keep this file free of Qt APIs so the test can run under Node.
//
// Fields:
//   name       the popout name, as passed to Popouts.openPanel() and
//              `qs ipc call popouts toggle <name>`
//   island     which bar section it hangs under when no caller says otherwise
//   source     the view, relative to the shell root (the popout host makes it
//              absolute against Quickshell.shellDir)
//   moduleId   the bar module that owns it, or "" for panels no module can
//              open. An owner-less panel must be left alone by the bar's
//              module sweep — that is the Tailscale bug above.
//
// Flags, both defaulting false, each replacing a hardcoded `=== "settings"`:
//   centerAnchored       ignores its opener's anchor and stays centred on the
//                        bar, re-centring when the bar's geometry changes
//   fillsBody            its view owns the whole popout body rather than
//                        being laid out inside the standard padding

var PANELS = [
    // The Fedora button is fixed bar furniture rather than a configurable
    // module. It still registers the panel's live anchor, but `control` stays
    // ownerless so module enablement and movement never close it.
    { name: "control", island: "right", moduleId: "", source: "Popovers/ControlCenterPopover.qml" },

    // The three glanceable views each belong to the widget that presents
    // them. Their names remain the established IPC names.
    { name: "calendar", island: "center", moduleId: "clock", source: "Popovers/CalendarPopover.qml" },
    { name: "weather", island: "center", moduleId: "weather", source: "Popovers/WeatherPopover.qml" },
    { name: "notifications", island: "right", moduleId: "notifications", source: "Popovers/NotifsPopover.qml" },
    { name: "reminders", island: "center", moduleId: "indicators", source: "Popovers/ReminderPopover.qml" },

    { name: "media", island: "left", moduleId: "media", source: "Popovers/MediaPopover.qml" },
    { name: "usage", island: "right", moduleId: "usage", source: "Popovers/UsagePopover.qml" },
    { name: "t3code", island: "right", moduleId: "t3", source: "Popovers/T3CodePopover.qml" },
    { name: "github", island: "right", moduleId: "gh", source: "Popovers/GitHubPopover.qml" },
    { name: "updates", island: "right", moduleId: "updates", source: "Popovers/UpdatesPopover.qml" },

    // Each status widget owns its established dedicated view. The names stay
    // stable for `qs ipc call popouts toggle <name>` and in-panel drill-ins.
    { name: "audio", island: "right", moduleId: "vol", source: "Popovers/AudioPopover.qml" },
    { name: "wifi", island: "right", moduleId: "wifi", source: "Popovers/WifiPopover.qml" },
    { name: "bluetooth", island: "right", moduleId: "bt", source: "Popovers/BluetoothPopover.qml" },
    { name: "battery", island: "right", moduleId: "batt", source: "Popovers/BatteryPopover.qml" },

    // Opened from the Control Panel tile, not from a bar module of its own.
    { name: "tailscale", island: "right", moduleId: "", source: "Popovers/TailscalePopover.qml" },

    // Opened from the settings window and from IPC. The only panel carrying
    // any of the three flags; they exist so no consumer has to name it.
    {
        name: "settings",
        island: "center",
        moduleId: "",
        source: "Settings/SettingsView.qml",
        centerAnchored: true,
        fillsBody: true
    }
];

// Bar modules that own no panel of their own. `ws` has no detail view and
// `tray` opens each item's own menu. Listed so the test can insist the module
// id and panel spaces account for each other completely rather than silently
// tolerating a typo'd moduleId.
var PANEL_LESS_MODULES = ["ws", "tray"];

var SETTINGS = "settings";

function byName(name) {
    for (var i = 0; i < PANELS.length; i++) {
        if (PANELS[i].name === name)
            return PANELS[i];
    }
    return null;
}

function names() {
    return PANELS.map(function (p) { return p.name; });
}

function island(name) {
    var panel = byName(name);
    return panel ? panel.island : "right";
}

function moduleFor(name) {
    var panel = byName(name);
    return panel ? panel.moduleId : "";
}

function panelForModule(moduleId) {
    for (var i = 0; i < PANELS.length; i++) {
        if (PANELS[i].moduleId === moduleId && moduleId !== "")
            return PANELS[i].name;
    }
    return "";
}

// True when no bar module can own this panel, so the bar's sweep for
// "the module behind the open popout went away" must skip it.
function ownerless(name) {
    return moduleFor(name) === "";
}

function centerAnchored(name) {
    var panel = byName(name);
    return !!(panel && panel.centerAnchored);
}

function fillsBody(name) {
    var panel = byName(name);
    return !!(panel && panel.fillsBody);
}

// { name: island } and { name: source }, for the QML properties that want a
// plain map to index rather than a call per lookup.
function islandMap() {
    var out = {};
    PANELS.forEach(function (p) { out[p.name] = p.island; });
    return out;
}

function sourceMap(prefix) {
    var base = prefix === undefined ? "" : prefix;
    var out = {};
    PANELS.forEach(function (p) { out[p.name] = base + p.source; });
    return out;
}

var exported = {
    PANELS: PANELS,
    PANEL_LESS_MODULES: PANEL_LESS_MODULES,
    SETTINGS: SETTINGS,
    byName: byName,
    names: names,
    island: island,
    moduleFor: moduleFor,
    panelForModule: panelForModule,
    ownerless: ownerless,
    centerAnchored: centerAnchored,
    fillsBody: fillsBody,
    islandMap: islandMap,
    sourceMap: sourceMap
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
