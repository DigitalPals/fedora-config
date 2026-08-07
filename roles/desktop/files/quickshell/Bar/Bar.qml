pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "Modules"
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
    // Balanced spacing: with Hyprland's gaps_out (10) on top of the
    // exclusive zone, windows end up exactly barTopMargin below the bar's
    // inner edge — the same gap as outside it. The -2 is tuned for the
    // floating gap; attached bars reserve their exact height. Auto-hide and
    // "reserve space" off both drop the zone entirely.
    exclusiveZone: Settings.autoHide || !Settings.exclusive ? 0
        : Theme.barTopMargin + Theme.barHeight - (Settings.floating ? 2 : 0)
    color: "transparent"

    // ---- auto-hide ----------------------------------------------------
    // The window stays mapped; only the content slides away and the input
    // mask shrinks to a thin reveal strip at the screen edge, so clicks
    // pass through the vacated area (design v2 Auto-hide).
    property bool revealed: true
    readonly property bool hidden: Settings.autoHide && !revealed && !Popouts.open
    property real hideShift: hidden
        ? (Settings.position === "top" ? -1 : 1) * (Theme.barTopMargin + Theme.barHeight + 12)
        : 0

    Behavior on hideShift {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
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

    // Audio, WifiState, BluetoothState, Battery and Media own the service
    // objects now; this window is a consumer like any popover. That matters
    // most for audio: the tracker that used to live here was instantiated
    // once per output.

    function popoutOpen(name) {
        return Popouts.open && Popouts.currentName === name;
    }

    // Published in window coordinates for the independent popout layer.
    // Keeping the menu in another Wayland surface prevents its Loader and
    // height changes from resizing/remapping the menubar itself.
    // The y here is deliberately position-independent: it encodes the
    // island's distance from the bar's fused screen edge, which is what the
    // popout geometry consumes — IslandPopout mirrors itself for bottom bars.
    readonly property rect leftIslandRect: Qt.rect(
        Theme.barSideMargin, Theme.barTopMargin,
        leftCluster.width, leftCluster.height)
    readonly property rect centerIslandRect: Qt.rect(
        Math.round((barWindow.width - centerCluster.width) / 2), Theme.barTopMargin,
        centerCluster.width, centerCluster.height)
    readonly property rect rightIslandRect: Qt.rect(
        barWindow.width - Theme.barSideMargin - rightCluster.width, Theme.barTopMargin,
        rightCluster.width, rightCluster.height)

    // Where a module sits, in the window coordinates the popout layer
    // uses: its panel hangs under the module itself rather than under the
    // section the module happens to live in.
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
        invalidateAnchorRects();
    }

    function unregisterPanel(name, item) {
        if (panelAnchors[name] === item) {
            delete panelAnchors[name];
            invalidateAnchorRects();
        }
    }

    // ---- anchor rect cache -------------------------------------------
    // hoverPanelAt runs on every pointer motion while a popout is open, and
    // mapped each registered module to window coordinates each time. The rects
    // only move when the layout does, so they are computed once per layout and
    // reused until something can have shifted them.
    //
    // Auto-hide is deliberately not an invalidation source: `hidden` requires
    // !Popouts.open, and hoverPanelAt returns early unless a popout is open, so
    // the slide can never be in progress while this cache is being read.
    property var cachedAnchorRects: null

    function invalidateAnchorRects() {
        cachedAnchorRects = null;
    }

    function anchorRects() {
        if (cachedAnchorRects !== null)
            return cachedAnchorRects;
        const out = [];
        for (const name of Object.keys(panelAnchors)) {
            const item = panelAnchors[name];
            if (!item || !item.visible || item.width <= 0 || item.height <= 0)
                continue;
            out.push({ name: name, item: item, rect: anchorOf(item) });
        }
        cachedAnchorRects = out;
        return out;
    }

    onCenterShiftChanged: invalidateAnchorRects()

    // The design's standing auto-rules: Media only while playing, Bluetooth
    // only when connected, Battery only on laptops (design v2 Modules page).
    function autoRule(id) {
        switch (id) {
        case "media": return Media.hasTrack;
        case "bt": return BluetoothState.connected;
        case "batt": return Battery.isLaptop;
        default: return true;
        }
    }

    function anyVisibleBefore(list, index) {
        for (let i = 0; i < index; i++) {
            if (list[i].on && autoRule(list[i].id))
                return true;
        }
        return false;
    }

    function anyVisibleAfter(list, index) {
        for (let i = index + 1; i < list.length; i++) {
            if (list[i].on && autoRule(list[i].id))
                return true;
        }
        return false;
    }

    function moduleCompact(id) {
        return compactIds.indexOf(id) !== -1;
    }

    function measuredSlots(repeater) {
        const entries = [];
        for (let i = 0; i < repeater.count; i++) {
            const slot = repeater.itemAt(i);
            if (!slot || !slot.active || slot.detailSaving <= 0)
                continue;
            entries.push({
                id: slot.modelData.id,
                col: slot.col,
                saving: slot.detailSaving,
                policy: slot.modelData.detail ?? "auto"
            });
        }
        return entries;
    }

    function reconstructedWidth(cluster, repeater) {
        let result = cluster.width;
        const slots = measuredSlots(repeater);
        for (const entry of slots) {
            if (moduleCompact(entry.id))
                result += entry.saving;
        }
        return result;
    }

    function recomputeFit() {
        invalidateAnchorRects();
        const entries = measuredSlots(leftRepeater)
            .concat(measuredSlots(centerRepeater), measuredSlots(rightRepeater));
        const result = LayoutHelpers.fitBar({
            width: width,
            sideMargin: Theme.barSideMargin,
            gutter: safetyGutter,
            widths: {
                left: reconstructedWidth(leftCluster, leftRepeater),
                center: reconstructedWidth(centerCluster, centerRepeater),
                right: reconstructedWidth(rightCluster, rightRepeater)
            },
            entries: entries
        });
        if (JSON.stringify(compactIds) !== JSON.stringify(result.compact))
            compactIds = result.compact;
        centerShift = result.centerOffset;
    }

    onWidthChanged: {
        // Ahead of the fit pass, which also invalidates: fitTimer has a zero
        // interval but still lands a turn later, and a motion event in
        // between would read rects from the old width.
        invalidateAnchorRects();
        fitTimer.restart();
    }

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
            // A panel no module owns (settings, tailscale) can never fail
            // this sweep honestly: moduleForPanel() is always null for it.
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
    // BarModule base, which is what lets the slot below hold them as a type
    // rather than duck-typing its way through Loader.item.
    readonly property var moduleSources: ({
        ws: "Modules/Workspaces.qml", media: "Modules/Media.qml",
        clock: "Modules/Clock.qml", weather: "Modules/Weather.qml",
        t3: "Modules/T3.qml", usage: "Modules/Usage.qml",
        vol: "Modules/Volume.qml", wifi: "Modules/Wifi.qml",
        batt: "Modules/Battery.qml", bell: "Modules/Bell.qml",
        bt: "Modules/Bluetooth.qml", idle: "Modules/Idle.qml",
        control: "Modules/Control.qml"
    })

    // One slot per configured module: loads the module's component when the
    // module is enabled and its auto-rule allows it, and hands composites
    // their island plus divider context.
    component ModuleSlot: Loader {
        id: slot

        required property var modelData
        required property int index
        property string col: "left"
        property var colList: []
        // `as` gives qmllint a typed handle on what the Loader built, so the
        // module contract below is checked rather than duck-typed.
        readonly property BarModule mod: item as BarModule
        readonly property real detailSaving: mod ? mod.detailSaving : 0

        anchors.verticalCenter: parent.verticalCenter
        // Every output carries a bar, but only the mapped one is visible;
        // the others must not instantiate a full set of modules (and their
        // timers) behind an unmapped surface.
        active: barWindow.visible && modelData.on && barWindow.autoRule(modelData.id)
        visible: active
        source: barWindow.moduleSources[slot.modelData.id] ?? ""
        onLoaded: {
            if (slot.mod) {
                slot.mod.host = barWindow;
                slot.mod.isle = slot.col;
                slot.mod.dividerBefore = Qt.binding(() =>
                    barWindow.anyVisibleBefore(slot.colList, slot.index));
                slot.mod.dividerAfter = Qt.binding(() =>
                    barWindow.anyVisibleAfter(slot.colList, slot.index));
            }
            fitTimer.restart();
        }
        onWidthChanged: fitTimer.restart()
        onDetailSavingChanged: fitTimer.restart()
    }

    function sameAnchor(a, b) {
        return Math.abs(a.x - b.x) < 0.5
            && Math.abs(a.y - b.y) < 0.5
            && Math.abs(a.width - b.width) < 0.5
            && Math.abs(a.height - b.height) < 0.5;
    }

    function togglePopout(name, isle, item) {
        Popouts.toggle(name, isle, anchorOf(item));
    }

    // Hover-to-open (caelestia): once a popout is open, hovering another
    // module switches straight to its popout — no click needed until the
    // popout is dismissed again.
    function hoverOpen(name, isle, item) {
        if (!Popouts.open || Popouts.currentName === name)
            return;
        // Mapping the separate popout surface can make Qt miss the next
        // MouseArea enter transition. Hover motion calls this too, so keep
        // an existing candidate armed rather than restarting its delay.
        if (pendingHoverName === name)
            return;
        pendingHoverName = name;
        pendingHoverIsland = isle;
        pendingHoverAnchor = anchorOf(item);
        hoverSwitch.restart();
    }

    function cancelHover(name) {
        if (pendingHoverName !== name)
            return;
        hoverSwitch.stop();
        pendingHoverName = "";
    }

    // The full-bar HoverHandler continues receiving pointer motion when a
    // second layer surface maps. Resolve that position back to registered
    // module anchors so switching does not depend on a MouseArea re-enter.
    function hoverPanelAt(position) {
        if (!Popouts.open)
            return;

        // Usage is registered as one stable popout anchor, but its providers
        // remain separate hover targets. Recover the provider before the
        // generic active-panel check so moving across an already-open Usage
        // module updates its content without moving the popout.
        const usageItem = panelAnchors.usage;
        if (usageItem && usageItem.visible
                && usageItem.providerAtScenePoint !== undefined) {
            const provider = usageItem.providerAtScenePoint(position);
            if (provider !== "") {
                Usage.selected = provider;
                if (Popouts.currentName === "usage") {
                    if (pendingHoverName !== "")
                        cancelHover(pendingHoverName);
                } else {
                    hoverOpen("usage", usageItem.isle ?? Popouts.defaultIsland.usage,
                        usageItem);
                }
                return;
            }
        }

        for (const entry of anchorRects()) {
            const rect = entry.rect;
            if (position.x < rect.x || position.x > rect.x + rect.width
                    || position.y < rect.y || position.y > rect.y + rect.height)
                continue;
            if (Popouts.currentName === entry.name) {
                if (pendingHoverName !== "")
                    cancelHover(pendingHoverName);
            } else {
                hoverOpen(entry.name,
                    entry.item.isle ?? Popouts.defaultIsland[entry.name], entry.item);
            }
            return;
        }
        if (pendingHoverName !== "")
            cancelHover(pendingHoverName);
    }

    property string pendingHoverName: ""
    property string pendingHoverIsland: ""
    property rect pendingHoverAnchor: Qt.rect(0, 0, 0, 0)

    Timer {
        id: hoverSwitch
        interval: 120
        onTriggered: {
            if (barWindow.pendingHoverName !== "" && Popouts.open)
                Popouts.openPanel(barWindow.pendingHoverName, barWindow.pendingHoverIsland,
                    barWindow.pendingHoverAnchor);
            barWindow.pendingHoverName = "";
        }
    }

    // IPC opens and transitions initiated inside a popout do not carry a new
    // module rectangle. The visible bar resolves every named module again so
    // the tab and panel always travel together, even when an old anchor is
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

    // One continuous menubar slab behind all three sections, rendered
    // beneath the popout surfaces so its shadow never falls on an open
    // panel.
    Item {
        x: Theme.barSideMargin
        y: barWindow.barY
        width: parent.width - 2 * Theme.barSideMargin
        height: Theme.barHeight

        transform: Translate {
            y: barWindow.hideShift
        }

        RectangularShadow {
            anchors.fill: barSlab
            radius: Theme.clusterRadius
            blur: 16
            spread: 0
            offset.y: 4
            color: Qt.rgba(0, 0, 0, 0.35)
        }

        Rectangle {
            id: barSlab
            width: parent.width
            height: Theme.barHeight
            radius: Theme.clusterRadius
            color: Theme.barBg
        }

        // Right-click anywhere on the slab opens Shell settings (design v2).
        // Module mouse areas only accept the left button, so right-clicks
        // fall through the layout layer to this area.
        MouseArea {
            anchors.fill: barSlab
            acceptedButtons: Qt.RightButton
            onClicked: Settings.togglePanel()
        }
    }

    // ---- layout ------------------------------------------------------

    Item {
        x: Theme.barSideMargin
        y: barWindow.barY
        width: parent.width - 2 * Theme.barSideMargin
        height: Theme.barHeight

        transform: Translate {
            y: barWindow.hideShift
        }

        // LEFT — workspaces + media
        Cluster {
            id: leftCluster
            anchors.left: parent.left
            padding: 5
            spacing: 2
            onWidthChanged: fitTimer.restart()

            Repeater {
                id: leftRepeater
                model: Settings.mods.left
                delegate: ModuleSlot { col: "left"; colList: Settings.mods.left }
            }

}

        // CENTER — clock + weather
        Cluster {
            id: centerCluster
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: barWindow.centerShift
            padding: 5
            spacing: 3
            onWidthChanged: fitTimer.restart()

            Repeater {
                id: centerRepeater
                model: Settings.mods.center
                delegate: ModuleSlot { col: "center"; colList: Settings.mods.center }
            }

}

        // RIGHT — the default home for model usage, audio, and status modules
        Cluster {
            id: rightCluster
            anchors.right: parent.right
            padding: 6
            spacing: 1
            onWidthChanged: fitTimer.restart()

            Repeater {
                id: rightRepeater
                model: Settings.mods.right
                delegate: ModuleSlot { col: "right"; colList: Settings.mods.right }
            }

}
    }

    // Only the clock module reads this, and that module exists only while
    // this bar is the mapped one. Re-enabling resyncs `date` in the same
    // turn, so a bar taking over from another output never shows a stale
    // time.
    SystemClock {
        id: clock
        enabled: barWindow.visible
        precision: Settings.modOpts.clock.seconds ? SystemClock.Seconds : SystemClock.Minutes
    }
}
