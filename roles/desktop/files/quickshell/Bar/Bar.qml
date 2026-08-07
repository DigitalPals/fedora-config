pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
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
    }

    function unregisterPanel(name, item) {
        if (panelAnchors[name] === item)
            delete panelAnchors[name];
    }

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

    readonly property var moduleComponents: ({
        ws: cmpWs, media: cmpMedia, clock: cmpClock, weather: cmpWeather,
        t3: cmpT3, usage: cmpUsage, vol: cmpVol, wifi: cmpWifi, batt: cmpBatt,
        bell: cmpBell, bt: cmpBt, idle: cmpIdle, control: cmpControl
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
        readonly property real detailSaving: item && "detailSaving" in item
            ? item.detailSaving : 0

        anchors.verticalCenter: parent.verticalCenter
        // Every output carries a bar, but only the mapped one is visible;
        // the others must not instantiate a full set of modules (and their
        // timers) behind an unmapped surface.
        active: barWindow.visible && modelData.on && barWindow.autoRule(modelData.id)
        visible: active
        sourceComponent: barWindow.moduleComponents[slot.modelData.id]
        onLoaded: {
            if ("isle" in item)
                item.isle = slot.col;
            if ("dividerBefore" in item)
                item.dividerBefore = Qt.binding(() =>
                    barWindow.anyVisibleBefore(slot.colList, slot.index));
            if ("dividerAfter" in item)
                item.dividerAfter = Qt.binding(() =>
                    barWindow.anyVisibleAfter(slot.colList, slot.index));
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

        const names = Object.keys(panelAnchors);
        for (const name of names) {
            const item = panelAnchors[name];
            if (!item || !item.visible || item.width <= 0 || item.height <= 0)
                continue;
            const rect = anchorOf(item);
            if (position.x < rect.x || position.x > rect.x + rect.width
                    || position.y < rect.y || position.y > rect.y + rect.height)
                continue;
            if (Popouts.currentName === name) {
                if (pendingHoverName !== "")
                    cancelHover(pendingHoverName);
            } else {
                hoverOpen(name, item.isle ?? Popouts.defaultIsland[name], item);
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

            Component {
                id: cmpWs

                Workspaces {
                    property string isle: "left"
                }
            }

            Component {
                id: cmpMedia

                Row {
                    id: mediaModule

                    property string isle: "left"
                    property bool dividerBefore: false
                    spacing: 2
                    readonly property real detailSaving: mediaTitle.implicitWidth > 0
                        ? Math.min(mediaTitle.implicitWidth, Settings.modOpts.media.maxWidth) + 6 : 0

                    Component.onCompleted: barWindow.registerPanel("media", mediaChip)
                    Component.onDestruction: barWindow.unregisterPanel("media", mediaChip)

                    Divider {
                        visible: mediaModule.dividerBefore
                    }

            BarChip {
                id: mediaChip
                visible: Media.hasTrack
                held: barWindow.popoutOpen("media")
                tooltip: Media.player ? Media.player.trackTitle : "Media"
                onEntered: barWindow.hoverOpen("media", mediaModule.isle, mediaChip)
                onExited: barWindow.cancelHover("media")
                onClicked: barWindow.togglePopout("media", mediaModule.isle, mediaChip)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Media.glyph
                    font.family: Theme.fontIcon
                    font.pixelSize: Theme.barIconSize
                    color: mediaChip.held || mediaChip.hovered ? Theme.textHi : Theme.icon

                    Behavior on color {
                        ColorAnimation { duration: Theme.chipFadeDuration }
                    }
                }

                Text {
                    id: mediaTitle
                    visible: !barWindow.moduleCompact("media")
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (!Media.player)
                            return "";
                        const format = Settings.modOpts.media.titleFormat;
                        const artist = Media.player.trackArtist;
                        const title = Media.player.trackTitle;
                        if (format === "title" || !artist)
                            return title;
                        return format === "artist-title"
                            ? artist + " — " + title : title + " — " + artist;
                    }
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.barTextSize
                    color: mediaChip.held || mediaChip.hovered ? Theme.textHi : Theme.textMid
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, Settings.modOpts.media.maxWidth)

                    Behavior on color {
                        ColorAnimation { duration: Theme.chipFadeDuration }
                    }
                }
            }
                }
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

            Component {
                id: cmpClock

            BarChip {
                id: clockChip
                property string isle: "center"
                readonly property real detailSaving: Settings.modOpts.clock.showDate
                    ? clockDate.implicitWidth + 6 : 0

                Component.onCompleted: barWindow.registerPanel("calendar", clockChip)
                Component.onDestruction: barWindow.unregisterPanel("calendar", clockChip)

                held: barWindow.popoutOpen("calendar")
                tooltip: Qt.formatDateTime(clock.date, "dddd, MMMM d")
                onEntered: barWindow.hoverOpen("calendar", clockChip.isle, clockChip)
                onExited: barWindow.cancelHover("calendar")
                onClicked: barWindow.togglePopout("calendar", clockChip.isle, clockChip)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDateTime(clock.date, Settings.clock24
                        ? (Settings.modOpts.clock.seconds ? "HH:mm:ss" : "HH:mm")
                        : (Settings.modOpts.clock.seconds ? "h:mm:ss AP" : "h:mm AP"))
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.barTextSize
                    font.weight: Theme.weightSemibold
                    font.features: Theme.tabularNumberFeatures
                    color: Theme.textHi
                }

                Text {
                    id: clockDate
                    visible: Settings.modOpts.clock.showDate && !barWindow.moduleCompact("clock")
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDateTime(clock.date, Settings.modOpts.clock.dateFormat)
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.barTextSize
                    font.features: Theme.tabularNumberFeatures
                    color: clockChip.held || clockChip.hovered ? Theme.textMid : Theme.textLow

                    Behavior on color {
                        ColorAnimation { duration: Theme.chipFadeDuration }
                    }
                }
            }
            }

            Component {
                id: cmpWeather

                Row {
                    id: weatherModule

                    property string isle: "center"
                    property bool dividerBefore: false
                    spacing: 3
                    // An enabled weather module stays on the bar while it is
                    // offline: a chip that vanishes cannot say why. Only the
                    // gap before the first forecast lands is blank.
                    readonly property bool shown: Weather.ready || Weather.offline
                    visible: shown
                    readonly property real detailSaving: weatherCondition.implicitWidth + 5

                    Component.onCompleted: barWindow.registerPanel("weather", weatherChip)
                    Component.onDestruction: barWindow.unregisterPanel("weather", weatherChip)

                    Divider {
                        visible: weatherModule.dividerBefore && weatherModule.shown
                    }

            // Quiet weather chip next to the clock (design 1g).
            BarChip {
                id: weatherChip
                visible: weatherModule.shown
                // One tighter than the default: the leading weather glyph
                // already carries its own side bearing.
                hPadding: 6
                spacing: 5
                held: barWindow.popoutOpen("weather")
                // Offline is the one state the chip cannot spell out in the
                // width it has, so the reason goes here.
                tooltip: Weather.place + " · "
                    + (Weather.offline ? Weather.fetchError : Weather.condition)
                onEntered: barWindow.hoverOpen("weather", weatherModule.isle, weatherChip)
                onExited: barWindow.cancelHover("weather")
                onClicked: barWindow.togglePopout("weather", weatherModule.isle, weatherChip)

                // Weather.code is -1 until a forecast lands, and both glyph()
                // and glyphColor() already answer that with the na mark in
                // Theme.textDim — no fallback needed here.
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Weather.glyph(Weather.code, Weather.isDay)
                    font.family: Theme.fontIcon
                    font.pixelSize: Theme.barIconSize
                    color: Weather.glyphColor(Weather.code, Weather.isDay)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    // Weather.temp is 0 with nothing loaded, and "0°" is a
                    // reading. A dash is not.
                    text: Weather.ready ? Weather.temp + "°" : "—"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.barTextSize
                    font.weight: Theme.weightSemibold
                    font.features: Theme.tabularNumberFeatures
                    // Dimmed while offline, so a forecast that has stopped
                    // being refreshed does not read as current.
                    color: Weather.offline ? Theme.textFaint : Theme.textMid
                }

                Text {
                    id: weatherCondition
                    visible: !barWindow.moduleCompact("weather")
                    anchors.verticalCenter: parent.verticalCenter
                    text: Weather.ready ? Weather.condition : "unavailable"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.barTextSize
                    color: weatherChip.held || weatherChip.hovered ? Theme.textMid : Theme.textLow

                    Behavior on color {
                        ColorAnimation { duration: Theme.chipFadeDuration }
                    }
                }
            }
                }
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

            Component {
                id: cmpT3

                Row {
                    id: t3Module

                    property string isle: "right"
                    property bool dividerBefore: false
                    spacing: 1
                    readonly property real detailSaving: Settings.modOpts.t3.showLabel
                        ? t3Chip.detailSaving : 0

                    Component.onCompleted: barWindow.registerPanel("t3code", t3Chip)
                    Component.onDestruction: barWindow.unregisterPanel("t3code", t3Chip)

                    Divider {
                        visible: t3Module.dividerBefore
                    }

                    T3Chip {
                        id: t3Chip
                        barVisible: barWindow.visible && !barWindow.hidden
                        displayMode: barWindow.moduleCompact("t3")
                            || !Settings.modOpts.t3.showLabel ? 0 : 2
                        held: barWindow.popoutOpen("t3code")
                        onClicked: barWindow.togglePopout("t3code", t3Module.isle, t3Chip)
                        onEntered: barWindow.hoverOpen("t3code", t3Module.isle, t3Chip)
                        onExited: barWindow.cancelHover("t3code")
                    }
                }
            }

            Component {
                id: cmpUsage

                Row {
                    id: usageModule

                    property string isle: "right"
                    property bool dividerBefore: false
                    property bool dividerAfter: false
                    spacing: 1
                    readonly property real detailSaving: usageChips.detailSaving

                    Component.onCompleted: barWindow.registerPanel("usage", usageChips)
                    Component.onDestruction: barWindow.unregisterPanel("usage", usageChips)

                    Divider {
                        visible: usageModule.dividerBefore
                    }

                    // Keep one anchor for the grouped provider module: changing
                    // Claude/Codex/Kimi content must not slide the panel.
                    UsageChips {
                        id: usageChips
                        property string isle: usageModule.isle
                        displayMode: barWindow.moduleCompact("usage") ? 0 : 2
                        held: barWindow.popoutOpen("usage")
                        onChipClicked: key => {
                            if (barWindow.popoutOpen("usage") && Usage.selected === key) {
                                Popouts.close();
                            } else {
                                Usage.selected = key;
                                Popouts.openPanel("usage", usageModule.isle,
                                    barWindow.anchorOf(usageChips));
                            }
                        }
                        onChipEntered: key => {
                            if (Popouts.open)
                                Usage.selected = key;
                            barWindow.hoverOpen("usage", usageModule.isle, usageChips);
                        }
                        onChipExited: barWindow.cancelHover("usage")
                    }

                    Divider {
                        visible: usageModule.dividerAfter
                    }
                }
            }

            Component {
                id: cmpIdle

                Row {
                    id: idleModule

                    property string isle: "right"
                    property bool dividerBefore: false
                    spacing: 1

                    Divider {
                        visible: idleModule.dividerBefore
                    }

                    // Keep-awake toggle. Lit while inhibiting; no popout, so
                    // it deliberately skips the hover-switch wiring.
                    BarIcon {
                        glyph: "" // coffee
                        active: SysInfo.idleInhibited
                        idleColor: Theme.textLow
                        tooltip: SysInfo.idleInhibited ? "Idle inhibit on" : "Idle inhibit off"
                        tooltipAlign: 1
                        onClicked: SysInfo.idleInhibited = !SysInfo.idleInhibited
                    }
                }
            }

            Component {
                id: cmpVol

            BarIcon {
                id: audioIcon
                property string isle: "right"

                Component.onCompleted: barWindow.registerPanel("audio", audioIcon)
                Component.onDestruction: barWindow.unregisterPanel("audio", audioIcon)
                glyph: Audio.muted || Audio.volume === 0 ? "" : Audio.volume < 50 ? "" : ""
                label: Settings.modOpts.vol.showPct ? Audio.volume + "%" : ""
                compact: barWindow.moduleCompact("vol")
                held: barWindow.popoutOpen("audio")
                alert: Audio.muted
                tooltip: "Audio " + Audio.volume + "%"
                    + (Audio.muted ? " · muted" : "")
                    + " · wheel volume"
                    + (Settings.modOpts.vol.middleClick === "mute" ? " · middle mute" : "")
                tooltipAlign: 1
                onClicked: barWindow.togglePopout("audio", audioIcon.isle, audioIcon)
                onMiddleClicked: {
                    if (Settings.modOpts.vol.middleClick === "mute")
                        Audio.toggleMuted();
                }
                onWheeled: steps => Audio.stepVolume(steps * (Settings.modOpts.vol.step / 100))
                onEntered: barWindow.hoverOpen("audio", audioIcon.isle, audioIcon)
                onExited: barWindow.cancelHover("audio")
            }

            }

            Component {
                id: cmpWifi

            BarIcon {
                id: wifiIcon
                property string isle: "right"

                Component.onCompleted: barWindow.registerPanel("wifi", wifiIcon)
                Component.onDestruction: barWindow.unregisterPanel("wifi", wifiIcon)
                glyph: ""
                held: barWindow.popoutOpen("wifi")
                idleColor: WifiState.enabled ? (WifiState.connected ? Theme.icon : Theme.textLow) : Theme.textFaint
                tooltip: WifiState.connected ? "Wi-Fi · " + WifiState.name : "Wi-Fi"
                tooltipAlign: 1
                onClicked: barWindow.togglePopout("wifi", wifiIcon.isle, wifiIcon)
                onEntered: barWindow.hoverOpen("wifi", wifiIcon.isle, wifiIcon)
                onExited: barWindow.cancelHover("wifi")
            }

            }

            Component {
                id: cmpBt

            BarIcon {
                id: btIcon
                property string isle: "right"

                Component.onCompleted: barWindow.registerPanel("bluetooth", btIcon)
                Component.onDestruction: barWindow.unregisterPanel("bluetooth", btIcon)
                visible: BluetoothState.connected
                glyph: ""
                held: barWindow.popoutOpen("bluetooth")
                tooltip: "Bluetooth connected"
                tooltipAlign: 1
                onClicked: barWindow.togglePopout("bluetooth", btIcon.isle, btIcon)
                onEntered: barWindow.hoverOpen("bluetooth", btIcon.isle, btIcon)
                onExited: barWindow.cancelHover("bluetooth")
            }

            }

            Component {
                id: cmpBatt

            BarIcon {
                id: batteryIcon
                property string isle: "right"

                Component.onCompleted: barWindow.registerPanel("battery", batteryIcon)
                Component.onDestruction: barWindow.unregisterPanel("battery", batteryIcon)
                visible: Battery.isLaptop
                // md-battery_high / md-battery_charging_high. The charging
                // glyph carries its own bolt, so nothing is overlaid; it is
                // also wider, hence the fixed column below — 13.5 is what
                // the previous Font Awesome glyph laid out at, so the rest
                // of the cluster keeps its position.
                glyph: Battery.pluggedIn ? "󱊦" : "󱊣"
                glyphWidth: 13.5
                // An empty label also zeroes BarIcon's detailSaving, so
                // fitBar never budgets for a percentage that is never shown.
                label: Settings.modOpts.batt.showPct ? Math.round(Battery.percent) + "%" : ""
                compact: barWindow.moduleCompact("batt")
                alert: !Battery.pluggedIn && Battery.percent <= Settings.modOpts.batt.critAt
                held: barWindow.popoutOpen("battery")
                idleColor: Battery.pluggedIn ? Theme.accent : Battery.percent <= Settings.modOpts.batt.warnAt ? Theme.amber : Theme.icon
                tooltip: "Battery " + Math.round(Battery.percent) + "%"
                    + (Battery.state === "charging" ? " · charging"
                        : Battery.state === "full" ? " · fully charged" : "")
                tooltipAlign: 1
                onClicked: barWindow.togglePopout("battery", batteryIcon.isle, batteryIcon)
                onEntered: barWindow.hoverOpen("battery", batteryIcon.isle, batteryIcon)
                onExited: barWindow.cancelHover("battery")
            }

            }

            Component {
                id: cmpBell

            Item {
                id: bellModule
                property string isle: "right"

                Component.onCompleted: barWindow.registerPanel("notifications", bellModule)
                Component.onDestruction: barWindow.unregisterPanel("notifications", bellModule)
                width: bellIcon.width
                height: Theme.barHeight
                anchors.verticalCenter: parent.verticalCenter

                BarIcon {
                    id: bellIcon
                    glyph: ""
                    tooltip: Notifs.count + (Notifs.count === 1 ? " notification" : " notifications")
                    tooltipAlign: 1
                    held: barWindow.popoutOpen("notifications")
                    onClicked: barWindow.togglePopout("notifications", bellModule.isle, bellIcon)
                    onEntered: barWindow.hoverOpen("notifications", bellModule.isle, bellIcon)
                    onExited: barWindow.cancelHover("notifications")
                }

                Rectangle {
                    id: bellBadge
                    readonly property bool showCount: Settings.modOpts.bell.badge === "count"
                    visible: Notifs.count > 0 && Settings.modOpts.bell.badge !== "off"
                    anchors.top: bellIcon.top
                    anchors.topMargin: showCount ? -3 : -1
                    anchors.right: bellIcon.right
                    anchors.rightMargin: showCount ? 0 : 3
                    width: showCount ? Math.max(height, badgeCount.implicitWidth + 8) : 10
                    height: showCount ? 15 : 10
                    radius: height / 2
                    // Count mode is a single accent pill ringed in bar color;
                    // dot mode keeps the original barBg ring + inner dot.
                    color: showCount
                        ? (Notifs.hasUrgent ? Theme.red : Theme.accent) : Theme.barBg
                    border.width: showCount ? 1 : 0
                    border.color: Theme.barBg

                    Rectangle {
                        visible: !bellBadge.showCount
                        anchors.centerIn: parent
                        width: 6
                        height: 6
                        radius: 3
                        color: Notifs.hasUrgent ? Theme.red : Theme.accent
                    }

                    Text {
                        id: badgeCount
                        visible: bellBadge.showCount
                        anchors.centerIn: parent
                        text: Notifs.count > 99 ? "99+" : Notifs.count
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontCaption
                        font.weight: Theme.weightSemibold
                        font.features: Theme.tabularNumberFeatures
                        color: Theme.accentFg
                    }
                }
            }

            }

            Component {
                id: cmpControl

                BarIcon {
                    id: controlIcon
                    property string isle: "right"

                    Component.onCompleted: barWindow.registerPanel("control", controlIcon)
                    Component.onDestruction: barWindow.unregisterPanel("control", controlIcon)
                    glyph: "\uf30a" // fedora logo — Control Center trigger
                    glyphSize: Theme.barIconSize
                    active: barWindow.popoutOpen("control")
                    tooltip: "Control Center"
                    tooltipAlign: 1
                    onClicked: barWindow.togglePopout("control", controlIcon.isle, controlIcon)
                    onEntered: barWindow.hoverOpen("control", controlIcon.isle, controlIcon)
                    onExited: barWindow.cancelHover("control")
                }
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
