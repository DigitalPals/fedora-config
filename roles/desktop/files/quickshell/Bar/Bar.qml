pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import "../Common"
import "../Common/BarGeometry.js" as BarGeometry
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
    // Follow the clock's local geometry synchronously. Updating this from the
    // deferred fit pass left it one rendered frame behind an animated child,
    // which showed up as a right/left rebound during indicator disclosure.
    readonly property real centerPinBias: {
        void slotRegistryRevision;
        const actual = currentCenterExtents();
        return centerCluster.width / 2 - actual.left;
    }
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
    property bool indicatorActionHovered: false
    // Indicators owns the width spring while its inactive block opens or
    // closes. The center pill observes this to avoid wrapping that motion in
    // its older width animation and making the clock rebound.
    property bool indicatorDisclosureAnimating: false
    property point tooltipPointerPosition: Qt.point(-1, -1)
    readonly property int safetyGutter: 8
    readonly property int closedHeight: Theme.barTopMargin + Theme.barHeight + 34
    readonly property string outputName: screen ? screen.name : ""
    readonly property bool popoutHost: outputName !== ""
        && Popouts.hostScreenName === outputName
    readonly property bool popoutActive: popoutHost && Popouts.open
    implicitHeight: closedHeight
    // The bar edge's y inside this window: hugging the anchored screen edge
    // with the configured gap on either position.
    readonly property real barY: BarGeometry.barY({
        style: Settings.barStyle,
        gap: Settings.gap,
        height: Theme.barHeight,
        position: Settings.position,
        windowHeight: height
    })
    // Balanced spacing: with Hyprland's gaps_out on top of the exclusive
    // zone, windows end up exactly barTopMargin below the bar's inner edge —
    // the same gap as outside it. Auto-hide and "reserve space" off both drop
    // the zone entirely.
    exclusiveZone: BarGeometry.exclusiveZone({
        style: Settings.barStyle,
        gap: Settings.gap,
        height: Theme.barHeight,
        autoHide: Settings.autoHide,
        exclusive: Settings.exclusive
    })
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
    readonly property bool hidden: Settings.autoHide && !revealed && !popoutActive
    property real hideShift: hidden ? BarGeometry.hideShift({
        style: Settings.barStyle,
        gap: Settings.gap,
        height: Theme.barHeight,
        position: Settings.position
    }) : 0

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

    // One bar exists per output, but only the focused bar carries the Wayland
    // inhibitor. SysInfo's systemd-inhibit is what actually holds the session
    // awake, so duplicating this per output would add no protection.
    IdleInhibitor {
        window: barWindow
        enabled: SysInfo.idleInhibited && barWindow.visible
            && barWindow.screen === Screens.focused
    }

    function popoutOpen(name) {
        return popoutActive && Popouts.currentName === name;
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
        Math.round((barWindow.width - centerCluster.width) / 2
            + barWindow.centerPinBias + barWindow.animatedCenterShift), Theme.barTopMargin,
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
            || Updates.runState !== "idle";
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
        for (const device of EthernetState.connectedDevices)
            parts.push("Ethernet " + (device.connection || device.device));
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
    // Object key mutation has no QML notify signal of its own. This revision
    // makes bindings that resolve a registered slot rerun on lifecycle changes.
    property int slotRegistryRevision: 0

    function registerSlot(id, slot) {
        slotRegistry[id] = slot;
        slotRegistryRevision++;
        scheduleFit();
    }

    function unregisterSlot(id, slot) {
        if (slotRegistry[id] === slot) {
            delete slotRegistry[id];
            slotRegistryRevision++;
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
        const metrics = currentCenterExtents();
        for (const id of Object.keys(slotRegistry)) {
            const slot = slotRegistry[id];
            if (!slot || !slot.active || slot.detailSaving <= 0)
                continue;
            entries.push({
                id: id,
                col: slot.col,
                saving: slot.detailSaving,
                policy: slot.modelData.detail ?? "auto",
                centerSide: slot.col === "center" && id !== "clock"
                    && slot.mapToItem(centerCluster, 0, 0).x + slot.width / 2
                        <= metrics.left ? "left" : "right"
            });
        }
        return entries;
    }

    function itemCenterXWithin(item, ancestor) {
        let position = item.width / 2;
        let current = item;
        // Read every intermediate x explicitly. mapToItem() returns the same
        // number, but its internal transform walk does not expose those notify
        // dependencies to a QML binding, leaving the clock pin one layout
        // update behind a Row whose preceding child is changing width.
        while (current && current !== ancestor) {
            position += current.x;
            current = current.parent;
        }
        return current === ancestor ? position : ancestor.width / 2;
    }

    function currentClockPin() {
        const clockSlot = slotRegistry.clock;
        if (clockSlot && clockSlot.active && clockSlot.col === "center")
            return itemCenterXWithin(clockSlot, centerCluster);
        return centerCluster.width / 2;
    }

    function currentCenterExtents() {
        const pin = currentClockPin();
        return {
            left: Math.max(0, pin),
            right: Math.max(0, centerCluster.width - pin)
        };
    }

    function reconstructedCenterExtents(entries) {
        const actual = currentCenterExtents();
        const result = { left: actual.left, right: actual.right };
        for (const entry of entries) {
            if (entry.col !== "center" || !moduleCompact(entry.id))
                continue;
            const side = entry.centerSide === "left" ? "left" : "right";
            result[side] += entry.saving;
        }
        return result;
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
        const centerExtents = reconstructedCenterExtents(entries);
        const result = LayoutHelpers.fitBar({
            width: width,
            sideMargin: Theme.barSideMargin + Theme.barPadding,
            gutter: safetyGutter,
            widths: {
                left: reconstructedWidth(leftSection.width, "left", entries),
                center: reconstructedWidth(centerCluster.width, "center", entries),
                right: reconstructedWidth(rightSection.width, "right", entries)
            },
            centerExtents: centerExtents,
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
            // Every output runs this handler, but only the popout's host owns
            // the module whose detached panel is open.
            // A panel no module owns (settings, control, tailscale) can never
            // fail this sweep honestly: moduleForPanel() is always null for it.
            if (!barWindow.popoutActive
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
        indicators: "Modules/Indicators.qml",
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
        Popouts.toggle(name, isle, anchorOf(item), outputName);
    }

    function openPopout(name, isle, item) {
        Popouts.openPanel(name, isle, anchorOf(item), outputName);
    }

    // Desktop-menu semantics: a click latches the menu session open, then
    // crossing another menu-bearing item switches the existing surface in
    // place. Hovering a closed bar remains inert; the focus grab closes the
    // session on the next click outside it.
    function hoverPopout(name, isle, item) {
        if (!Popouts.open)
            return false;
        if (!popoutOpen(name))
            openPopout(name, isle, item);
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
    // module rectangle. Only the popout's owning bar may resolve that module:
    // every output is visible now, and letting all of them publish their local
    // rectangle makes different-sized outputs bounce the shared anchor forever.
    Connections {
        target: Popouts

        function onChanged() {
            if (!barWindow.popoutActive)
                return;
            Qt.callLater(() => {
                if (!barWindow.popoutActive)
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
        height: Theme.barTopMargin + Theme.barHeight
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
                const indicatorSlot = barWindow.slotRegistry.indicators;
                barWindow.indicatorActionHovered = indicatorSlot !== undefined
                    && indicatorSlot.mod !== null
                    && indicatorSlot.mod.actionAtScenePoint(scenePoint);
            }

            onHoveredChanged: {
                if (hovered) {
                    hideTimer.stop();
                    barWindow.revealed = true;
                } else if (Settings.autoHide) {
                    hideTimer.restart();
                }
                if (!hovered)
                    barWindow.indicatorActionHovered = false;
            }
        }
    }

    // ---- the slab ------------------------------------------------------
    // One continuous surface. In glass mode the compositor supplies the blur
    // behind its tint (see roles/desktop/files/looknfeel.lua); solid mode uses
    // the same selected menubar color at full opacity.
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
            color: Theme.barSurface

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

        }

        HugCorner {
            visible: Theme.barHug
            x: 0
            y: Settings.position === "top" ? parent.height : -height
            bottomCorner: Settings.position === "bottom"
            fillColor: Theme.barSurface
        }

        HugCorner {
            visible: Theme.barHug
            x: parent.width - width
            y: Settings.position === "top" ? parent.height : -height
            rightCorner: true
            bottomCorner: Settings.position === "bottom"
            fillColor: Theme.barSurface
        }

        // Right-click anywhere on the slab opens Shell settings. Module mouse
        // areas only accept the left button, so right-clicks fall through the
        // layout layer to this area.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: Settings.togglePanel(undefined, barWindow.outputName)
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
                idleColor: Theme.barTextMid
                restFill: Launcher.open && Launcher.screen === barWindow.screen
                    ? Theme.barChipHover : Theme.barChip
                tooltip: "Apps  ·  Super Space"
                tooltipAlign: -1
                onClicked: Launcher.toggle(barWindow.screen)
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
            // Algebraically this is the former centered anchor plus pin bias,
            // but as one binding it cannot render between the two halves of
            // that cancellation. The clock's local center is the only moving
            // input while indicators disclose on its left.
            x: parent.width / 2 - barWindow.currentClockPin()
                + barWindow.animatedCenterShift
            anchors.verticalCenter: parent.verticalCenter
            onImplicitWidthChanged: barWindow.scheduleFit()
        }

        // RIGHT — configured modules, then power. Recording now lives beside
        // the clock with the other active quick actions.
        Row {
            id: rightSection
            anchors.right: parent.right
            anchors.rightMargin: Theme.barPadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

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
                idleColor: Theme.barTextMid
                hoverColor: Theme.barRedText
                tooltip: "Power"
                tooltipAlign: 1
                onClicked: Session.openMenu(barWindow.screen)
            }
        }
    }
}
