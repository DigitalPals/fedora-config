pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import "../Common"
import "../Common/LayoutHelpers.js" as LayoutHelpers
import "../Common/PanelRegistryData.js" as PanelRegistry

PanelWindow {
    id: barWindow

    anchors {
        top: Settings.position === "top"
        bottom: Settings.position === "bottom"
        left: true
        right: true
    }
    property var compactIds: []
    property real centerShift: 0
    // What the centre pill is actually drawn at. The fit pass moves
    // `centerShift` in one step when a module appears or the bar is resized;
    // routing it through a second property lets the pill glide there, and a
    // Behavior cannot be attached to a grouped anchor property directly.
    property real animatedCenterShift: centerShift

    Behavior on animatedCenterShift {
        enabled: barWindow.animationsReady
        NumberAnimation {
            duration: Theme.expandDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.springCurve
        }
    }
    // Shared pointer truth for tooltips. Individual MouseAreas can miss an
    // exit when the pointer leaves this layer surface, while the full-window
    // handler below still reports that the bar itself is no longer hovered.
    readonly property bool tooltipPointerInside: barHover.hovered
    property point tooltipPointerPosition: Qt.point(-1, -1)
    readonly property int safetyGutter: 8
    readonly property int closedHeight: Theme.barTopMargin + Theme.barHeight + 34
    implicitHeight: closedHeight
    // The bar edge's y inside this window: hugging the anchored screen edge
    // with the configured gap on either position.
    readonly property real barY: Settings.position === "top"
        ? Theme.barTopMargin : height - Theme.barTopMargin - Theme.barHeight
    // Balanced spacing: with Hyprland's gaps_out on top of the exclusive
    // zone, windows end up exactly barTopMargin below the bar's inner edge —
    // the same gap as outside it. Auto-hide and "reserve space" off both drop
    // the zone entirely.
    exclusiveZone: Settings.autoHide || !Settings.exclusive ? 0
        : Theme.barTopMargin + Theme.barHeight - (Settings.floating ? 2 : 0)
    color: "transparent"

    // Geometry animations stay off until the bar has laid itself out once, so
    // the first frame is the finished bar rather than a pill growing out of
    // nothing on every shell start.
    property bool animationsReady: false

    Timer {
        id: settleTimer
        interval: 240
        running: true
        onTriggered: barWindow.animationsReady = true
    }

    // ---- auto-hide ----------------------------------------------------
    // The window stays mapped; only the content slides away and the input
    // mask shrinks to a thin reveal strip at the screen edge, so clicks
    // pass through the vacated area.
    property bool revealed: true
    readonly property bool hidden: Settings.autoHide && !revealed && !Popouts.open
    property real hideShift: hidden
        ? (Settings.position === "top" ? -1 : 1) * (Theme.barTopMargin + Theme.barHeight + 12)
        : 0

    Behavior on hideShift {
        NumberAnimation {
            duration: Theme.expandDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.springCurve
        }
    }

    Timer {
        id: hideTimer
        interval: 1600
        onTriggered: {
            if (Settings.autoHide && !barHover.hovered)
                barWindow.revealed = false;
        }
    }

    Connections {
        target: Settings

        function onAutoHideChanged() {
            if (Settings.autoHide) {
                hideTimer.restart();
            } else {
                hideTimer.stop();
                barWindow.revealed = true;
            }
        }

        function onPanelOpenChanged() {
            if (!Settings.panelOpen && Settings.autoHide)
                hideTimer.restart();
        }
    }

    Connections {
        target: Popouts

        function onOpenChanged() {
            if (!Popouts.open && Settings.autoHide)
                hideTimer.restart();
        }
    }

    // A persisted auto-hide setting does not emit onAutoHideChanged during
    // construction, so explicitly arm the initial idle countdown.
    Component.onCompleted: {
        if (Settings.autoHide)
            hideTimer.restart();
    }

    mask: Region { item: barWindow.hidden ? revealStrip : barStrip }

    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "qs-bar"

    // ---- shared service state ----------------------------------------

    // One bar exists per output; only the mapped one can carry a Wayland
    // inhibitor. SysInfo's systemd-inhibit is what actually holds the
    // session awake, so nothing is lost while this one is idle.
    IdleInhibitor {
        window: barWindow
        enabled: SysInfo.idleInhibited && barWindow.visible
    }

    function popoutOpen(name) {
        return Popouts.open && Popouts.currentName === name;
    }

    // Published in window coordinates for the independent popout layer.
    // Keeping the panels in another Wayland surface prevents their Loader and
    // height changes from resizing/remapping the menubar itself.
    // The y here is deliberately position-independent: it encodes the
    // section's distance from the bar's anchored screen edge, which is what
    // the popout geometry consumes — PopoutHost mirrors itself for bottom bars.
    readonly property rect leftIslandRect: Qt.rect(
        Theme.barSideMargin, Theme.barTopMargin,
        leftSection.width + Theme.barPadding, Theme.barHeight)
    readonly property rect centerIslandRect: Qt.rect(
        Math.round((barWindow.width - centerCluster.width) / 2), Theme.barTopMargin,
        Math.max(1, centerCluster.width), Theme.barHeight)
    readonly property rect rightIslandRect: Qt.rect(
        barWindow.width - Theme.barSideMargin - rightSection.width - Theme.barPadding,
        Theme.barTopMargin,
        rightSection.width + Theme.barPadding, Theme.barHeight)

    // Where a module sits, in the window coordinates the popout layer uses:
    // its panel hangs under the module itself rather than under the section
    // the module happens to live in.
    function anchorOf(item) {
        const p = item.mapToItem(null, 0, 0);
        return Qt.rect(p.x, p.y, item.width, item.height);
    }

    // Panel-name → module item, maintained by the settings-driven module
    // components as their Loaders create and destroy them. Read only from
    // imperative code paths, so plain mutation without notify is fine.
    property var panelAnchors: ({})

    function registerPanel(name, item) {
        panelAnchors[name] = item;
    }

    function unregisterPanel(name, item) {
        if (panelAnchors[name] === item)
            delete panelAnchors[name];
    }

    // Whether a module is on screen at all, beyond the user having enabled it:
    // media only while something is playing, Bluetooth only when connected,
    // battery only on laptops, weather once there is either a forecast or a
    // reason there is not, and the two modules that are their own reason to
    // exist — the updates chip and the tray — only while they have something
    // to show.
    //
    // Every such rule belongs here and nowhere else. The bar's dividers and its
    // group pills read the same function, so a module that hid itself by some
    // other means would leave a separator with nothing on one side of it and a
    // pill with nothing inside it.
    function autoRule(id) {
        switch (id) {
        case "media": return Media.hasTrack;
        case "weather": return Weather.ready || Weather.offline;
        case "bt": return BluetoothState.connected;
        case "batt": return Battery.isLaptop;
        case "updates": return Updates.total > 0 || Updates.error !== ""
            || (Updates.ran && Updates.busy);
        case "tray": return SystemTray.items.values.length > 0;
        default: return true;
        }
    }

    function moduleShown(entry) {
        return !!entry && entry.on === true && autoRule(entry.id);
    }

    function moduleCompact(id) {
        return compactIds.indexOf(id) !== -1;
    }

    // What the status pill says when hovered — it stands in for four modules
    // that no longer have tooltips of their own.
    readonly property string statusSummary: {
        const parts = [];
        if (WifiState.enabled && WifiState.connected)
            parts.push("Wi-Fi " + WifiState.name);
        else if (WifiState.enabled)
            parts.push("Wi-Fi off-network");
        if (BluetoothState.connected)
            parts.push("Bluetooth connected");
        parts.push("Volume " + Audio.volume + "%" + (Audio.muted ? " (muted)" : ""));
        if (Battery.isLaptop)
            parts.push("Battery " + Math.round(Battery.percent) + "%");
        return parts.join(" · ");
    }

    // ---- fit pass ------------------------------------------------------
    // Live ModuleSlots, keyed by module id. The clusters nest their slots
    // inside group pills, so the fit pass registers them here on the way in
    // rather than trying to walk two levels of Repeater back out.
    property var slotRegistry: ({})

    function registerSlot(id, slot) {
        slotRegistry[id] = slot;
        scheduleFit();
    }

    function unregisterSlot(id, slot) {
        if (slotRegistry[id] === slot) {
            delete slotRegistry[id];
            scheduleFit();
        }
    }

    function scheduleFit() {
        fitTimer.restart();
    }

    // Every module that has detail text to give up, with what giving it up
    // would save and which column it would save it in.
    function measuredSlots() {
        const entries = [];
        for (const id of Object.keys(slotRegistry)) {
            const slot = slotRegistry[id];
            if (!slot || !slot.active || slot.detailSaving <= 0)
                continue;
            entries.push({
                id: id,
                col: slot.col,
                saving: slot.detailSaving,
                policy: slot.modelData.detail ?? "auto"
            });
        }
        return entries;
    }

    // The width a section would occupy with nothing compacted, which is what
    // the fit pass has to reason about — otherwise a module that has already
    // given up its label reads as small enough and never gets it back.
    function reconstructedWidth(width, col, entries) {
        let result = width;
        for (const entry of entries) {
            if (entry.col === col && moduleCompact(entry.id))
                result += entry.saving;
        }
        return result;
    }

    function recomputeFit() {
        const entries = measuredSlots();
        const result = LayoutHelpers.fitBar({
            width: width,
            sideMargin: Theme.barSideMargin + Theme.barPadding,
            gutter: safetyGutter,
            widths: {
                left: reconstructedWidth(leftSection.width, "left", entries),
                center: reconstructedWidth(centerCluster.width, "center", entries),
                right: reconstructedWidth(rightSection.width, "right", entries)
            },
            entries: entries
        });
        if (JSON.stringify(compactIds) !== JSON.stringify(result.compact))
            compactIds = result.compact;
        centerShift = result.centerOffset;
    }

    onWidthChanged: fitTimer.restart()

    Timer {
        id: fitTimer
        interval: 0
        onTriggered: barWindow.recomputeFit()
    }

    function moduleForPanel(name) {
        const item = panelAnchors[name];
        return item && item.visible ? item : null;
    }

    // A module disabled from the settings window takes its open popout with
    // it; callLater lets the Repeater rebuild settle first.
    Connections {
        target: Settings

        function onModsChanged() {
            fitTimer.restart();
            // Every output runs this handler, but only the mapped bar holds
            // the modules the open popout hangs under; the others would see
            // an empty panelAnchors and close someone else's panel.
            // A panel no module owns (settings, control, tailscale) can never
            // fail this sweep honestly: moduleForPanel() is always null for it.
            if (!barWindow.visible || !Popouts.open
                || PanelRegistry.ownerless(Popouts.currentName))
                return;
            Qt.callLater(() => {
                if (Popouts.open && !barWindow.moduleForPanel(Popouts.currentName))
                    Popouts.close();
            });
        }
    }

    // Module id -> its file. The modules live in Bar/Modules/ and share a
    // BarModule base, which is what lets ModuleSlot hold them as a type
    // rather than duck-typing its way through Loader.item.
    readonly property var moduleSources: ({
        ws: "Modules/Workspaces.qml", media: "Modules/Media.qml",
        clock: "Modules/Clock.qml", weather: "Modules/Weather.qml",
        t3: "Modules/T3.qml", usage: "Modules/Usage.qml",
        gh: "Modules/GitHub.qml", updates: "Modules/Updates.qml",
        tray: "Modules/Tray.qml",
        vol: "Modules/Volume.qml", wifi: "Modules/Wifi.qml",
        batt: "Modules/Battery.qml", bt: "Modules/Bluetooth.qml"
    })

    function sameAnchor(a, b) {
        return Math.abs(a.x - b.x) < 0.5
            && Math.abs(a.y - b.y) < 0.5
            && Math.abs(a.width - b.width) < 0.5
            && Math.abs(a.height - b.height) < 0.5;
    }

    function togglePopout(name, isle, item) {
        Popouts.toggle(name, isle, anchorOf(item));
    }

    // Desktop-menu semantics: a click latches the menu session open, then
    // crossing another menu-bearing item switches the existing surface in
    // place. Hovering a closed bar remains inert; the focus grab closes the
    // session on the next click outside it.
    function hoverPopout(name, isle, item) {
        if (!Popouts.open)
            return false;
        if (Popouts.currentName !== name)
            Popouts.openPanel(name, isle, anchorOf(item));
        return true;
    }

    function itemContainsPoint(item, position) {
        if (!item || !item.visible || item.width <= 0 || item.height <= 0)
            return false;
        const local = item.mapFromItem(null, position.x, position.y);
        return local.x >= 0 && local.x <= item.width
            && local.y >= 0 && local.y <= item.height;
    }

    // Mapping the detached layer surface can prevent a child MouseArea from
    // receiving its next enter or motion event. The bar-wide HoverHandler
    // keeps receiving pointer motion, so resolve its scene point against the
    // same registered anchors as a reliable second path.
    function hoverPanelAt(position) {
        if (!Popouts.open)
            return;

        // Usage owns one panel anchor but several provider targets. Resolve
        // the provider first; treating the whole group as a generic anchor
        // would open the right panel with whichever provider was selected last.
        const usageItem = panelAnchors.usage;
        if (usageItem && usageItem.visible
                && usageItem.providerAtScenePoint !== undefined) {
            const provider = usageItem.providerAtScenePoint(position);
            if (provider !== "") {
                Usage.selected = provider;
                hoverPopout("usage",
                    usageItem.isle || Popouts.defaultIsland.usage, usageItem);
                return;
            }
        }

        for (const name of Object.keys(panelAnchors)) {
            const item = panelAnchors[name];
            if (!itemContainsPoint(item, position))
                continue;
            hoverPopout(name, item.isle || Popouts.defaultIsland[name], item);
            return;
        }
    }

    // IPC opens and transitions initiated inside a popout do not carry a new
    // module rectangle. The visible bar resolves every named module again so
    // the panel always travels with its trigger, even when an old anchor is
    // still present from the previous view.
    Connections {
        target: Popouts

        function onChanged() {
            if (!barWindow.visible || !Popouts.open)
                return;
            Qt.callLater(() => {
                if (!barWindow.visible || !Popouts.open)
                    return;
                if (PanelRegistry.centerAnchored(Popouts.currentName)) {
                    if (Popouts.island !== "center" || Popouts.anchorRect.width !== 0) {
                        Popouts.island = "center";
                        Popouts.anchorRect = Qt.rect(0, 0, 0, 0);
                        Popouts.changed();
                    }
                    return;
                }
                const item = barWindow.moduleForPanel(Popouts.currentName);
                if (!item || item.width <= 0)
                    return;
                const anchor = barWindow.anchorOf(item);
                if (barWindow.sameAnchor(Popouts.anchorRect, anchor))
                    return;
                Popouts.anchorRect = anchor;
                Popouts.changed();
            });
        }
    }

    // Input region for the bar strip itself.
    Item {
        id: barStrip
        x: 0
        y: Settings.position === "top" ? 0 : barWindow.height - height
        width: parent.width
        height: Theme.barTopMargin + Theme.barHeight + 4
    }

    // Hover target while hidden: a thin strip hugging the bar's screen edge.
    Item {
        id: revealStrip
        x: 0
        y: Settings.position === "top" ? 0 : barWindow.height - height
        width: parent.width
        height: 8
    }

    // Tracks the pointer over whatever the window's input mask admits.
    Item {
        id: hoverLayer
        anchors.fill: parent
        z: 100

        HoverHandler {
            id: barHover
            blocking: false

            onPointChanged: {
                const scenePoint = hoverLayer.mapToItem(null,
                    point.position.x, point.position.y);
                barWindow.tooltipPointerPosition = scenePoint;
                barWindow.hoverPanelAt(scenePoint);
            }

            onHoveredChanged: {
                if (hovered) {
                    hideTimer.stop();
                    barWindow.revealed = true;
                } else if (Settings.autoHide) {
                    hideTimer.restart();
                }
            }
        }
    }

    // ---- the slab ------------------------------------------------------
    // One continuous pane of glass. The compositor supplies the blur behind
    // it (see the layer rules in roles/desktop/files/looknfeel.lua); this
    // draws the tint, the rim light along the top edge, and the shadow that
    // lifts it off the wallpaper.
    Item {
        id: slabLayer
        x: Theme.barSideMargin
        y: barWindow.barY
        width: parent.width - 2 * Theme.barSideMargin
        height: Theme.barHeight

        transform: Translate {
            y: barWindow.hideShift
        }

        Rectangle {
            id: barSlab
            anchors.fill: parent
            radius: Theme.clusterRadius
            color: Theme.glass
            border.width: 1
            border.color: Theme.stroke

            Behavior on color {
                ColorAnimation { duration: Theme.surfaceDuration }
            }

            Behavior on radius {
                enabled: barWindow.animationsReady
                NumberAnimation {
                    duration: Theme.surfaceDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.springCurve
                }
            }

            // The inset highlight along the top edge. Clipped to its own upper
            // half so the rim follows the corners and then stops: unclipped it
            // closes into a ring and reads as a second border.
            Item {
                x: 1
                y: 1
                width: parent.width - 2
                height: Math.max(1, Theme.clusterRadius)
                clip: true

                Rectangle {
                    width: parent.width
                    height: Math.max(2, Theme.clusterRadius * 2)
                    radius: Math.max(0, Theme.clusterRadius - 1)
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.strokeHi
                }
            }
        }

        // Right-click anywhere on the slab opens Shell settings. Module mouse
        // areas only accept the left button, so right-clicks fall through the
        // layout layer to this area.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: Settings.togglePanel()
        }
    }

    // ---- layout ------------------------------------------------------

    Item {
        id: contentFrame
        x: Theme.barSideMargin
        y: barWindow.barY
        width: parent.width - 2 * Theme.barSideMargin
        height: Theme.barHeight

        transform: Translate {
            y: barWindow.hideShift
        }

        // LEFT — the launcher, then workspaces and media.
        Row {
            id: leftSection
            anchors.left: parent.left
            anchors.leftMargin: Theme.barPadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            BarIcon {
                host: barWindow
                shape: "round"
                glyph: "apps"
                glyphSize: Theme.iconMedium + 1
                glyphWeight: 500
                idleColor: Theme.textMid
                restFill: Launcher.open ? Theme.chipHover : Theme.chip
                tooltip: "Apps  ·  Super Space"
                tooltipAlign: -1
                onClicked: Launcher.toggle()
            }

            Cluster {
                id: leftCluster
                host: barWindow
                col: "left"
                model: Settings.mods.left
                onImplicitWidthChanged: barWindow.scheduleFit()
            }
        }

        // CENTER — clock, date and weather in one pill.
        Cluster {
            id: centerCluster
            host: barWindow
            col: "center"
            model: Settings.mods.center
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: barWindow.animatedCenterShift
            anchors.verticalCenter: parent.verticalCenter
            onImplicitWidthChanged: barWindow.scheduleFit()
        }

        // RIGHT — recording, then the configured modules, then power.
        Row {
            id: rightSection
            anchors.right: parent.right
            anchors.rightMargin: Theme.barPadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            RecordingChip {
                host: barWindow
            }

            Cluster {
                id: rightCluster
                host: barWindow
                col: "right"
                model: Settings.mods.right
                onImplicitWidthChanged: barWindow.scheduleFit()
            }

            BarIcon {
                host: barWindow
                shape: "round"
                glyph: "power_settings_new"
                glyphSize: Theme.iconMedium
                glyphWeight: 600
                idleColor: Theme.textMid
                hoverColor: Theme.redText
                tooltip: "Power"
                tooltipAlign: 1
                onClicked: Session.openMenu()
            }
        }
    }
}
