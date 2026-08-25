// What each bar widget is called on screen.
//
// The ids stay where they were: SettingsHelpers.MODULE_IDS is the schema the
// settings file is written in terms of, and renaming those would need a
// migration for no gain the user can see. This file owns only the words, so
// `wifi` can present itself as "Network" without touching a stored key.
//
// It exists as its own file because two surfaces now name a widget: the
// settings list, and the proxy that follows the pointer when a widget is
// dragged along the bar itself. Reading both from one table is what keeps
// them from drifting apart.
//
//   name    the full label — settings rows, drag proxies, announcements
//   short   the miniature label for the settings page's bar preview
//   tag     when the widget shows itself, when that is not "always"
//   detail  whether it has detail text the bar may compact away

var WIDGETS = {
    ws: { name: "Workspaces", short: "Workspaces" },
    media: { name: "Media", short: "Media", tag: "while playing", detail: true },
    indicators: { name: "Indicators", short: "Actions", tag: "clock-side" },
    clock: { name: "Clock", short: "Clock", detail: true },
    weather: { name: "Weather", short: "Weather", detail: true },
    t3: { name: "T3 Code", short: "T3", detail: true },
    usage: { name: "Model usage", short: "Usage", detail: true },
    gh: { name: "GitHub", short: "GH", detail: true },
    updates: { name: "Updates", short: "Updates", tag: "when pending", detail: true },
    tray: { name: "System tray", short: "Tray", tag: "when populated" },
    vol: { name: "Volume", short: "Vol", tag: "status pill", detail: true },
    wifi: { name: "Network", short: "Network", tag: "status pill" },
    bt: { name: "Bluetooth", short: "BT", tag: "when connected" },
    batt: { name: "Battery", short: "Batt", tag: "on laptops", detail: true }
};

// Never null: a widget id that outlived its catalog entry still has to draw a
// settings row and a drag proxy, and the raw id reads better there than a
// blank label would.
function widget(id) {
    return WIDGETS[id] || { name: id, short: id };
}

function widgetName(id) {
    return widget(id).name;
}

var exported = {
    WIDGETS: WIDGETS,
    widget: widget,
    widgetName: widgetName
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
