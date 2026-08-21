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
// Flags, all defaulting false, each replacing a hardcoded `=== "settings"`:
//   centerAnchored       ignores its opener's anchor and stays centred on the
//                        bar, re-centring when the bar's geometry changes
//   fillsBody            its view owns the whole popout body rather than
//                        being laid out inside the standard padding
//   persistsAcrossHosts  survives the focused output changing, because it can
//                        hand itself over to the newly live bar instead of
//                        being dismissed with the old one

var PANELS = [
    // The status pill — the volume/Wi-Fi/Bluetooth/battery glyphs sharing one
    // rounded background — is what opens the Control Center, so no single
    // module owns it. It is furniture the status modules fill in, not a
    // module of its own, which is why this panel is ownerless.
    { name: "control", island: "right", moduleId: "", source: "Popovers/ControlCenterPopover.qml" },

    // The centre pill (clock, date, weather) is the notification centre's
    // trigger, and that panel carries the calendar and the forecast with it.
    { name: "notifications", island: "center", moduleId: "clock", source: "Popovers/NotifCenterPopover.qml" },
    { name: "reminders", island: "center", moduleId: "indicators", source: "Popovers/ReminderPopover.qml" },

    { name: "media", island: "left", moduleId: "media", source: "Popovers/MediaPopover.qml" },
    { name: "usage", island: "right", moduleId: "usage", source: "Popovers/UsagePopover.qml" },
    { name: "t3code", island: "right", moduleId: "t3", source: "Popovers/T3CodePopover.qml" },
    { name: "github", island: "right", moduleId: "gh", source: "Popovers/GitHubPopover.qml" },
    { name: "updates", island: "right", moduleId: "updates", source: "Popovers/UpdatesPopover.qml" },

    // Reachable from IPC and from inside the Control Center, which is where
    // the redesign moved audio, Wi-Fi, Bluetooth and battery detail. Kept as
    // standalone panels so `qs ipc call popouts toggle wifi` still works and
    // so a keybind can go straight to one.
    { name: "calendar", island: "center", moduleId: "", source: "Popovers/CalendarPopover.qml" },
    { name: "weather", island: "center", moduleId: "", source: "Popovers/WeatherPopover.qml" },
    { name: "audio", island: "right", moduleId: "", source: "Popovers/AudioPopover.qml" },
    { name: "wifi", island: "right", moduleId: "", source: "Popovers/WifiPopover.qml" },
    { name: "bluetooth", island: "right", moduleId: "", source: "Popovers/BluetoothPopover.qml" },
    { name: "battery", island: "right", moduleId: "", source: "Popovers/BatteryPopover.qml" },

    // Opened from the Control Center tile, not from a bar module of its own.
    { name: "tailscale", island: "right", moduleId: "", source: "Popovers/TailscalePopover.qml" },

    // Opened from the settings window and from IPC. The only panel carrying
    // any of the three flags; they exist so no consumer has to name it.
    {
        name: "settings",
        island: "center",
        moduleId: "",
        source: "Settings/SettingsView.qml",
        centerAnchored: true,
        fillsBody: true,
        persistsAcrossHosts: true
    }
];

// Bar modules that own no panel of their own. `ws` has no detail view;
// `weather` rides inside the centre pill, whose panel the clock owns; `tray`
// opens each item's own menu; and the four status modules are glyphs inside
// the pill that opens the Control Center. Listed so the test can insist the
// module-id space and the panel space account for each other completely,
// rather than silently tolerating a typo'd moduleId.
var PANEL_LESS_MODULES = ["ws", "weather", "tray", "vol", "wifi", "bt", "batt"];

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

function persistsAcrossHosts(name) {
    var panel = byName(name);
    return !!(panel && panel.persistsAcrossHosts);
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
    persistsAcrossHosts: persistsAcrossHosts,
    islandMap: islandMap,
    sourceMap: sourceMap
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
