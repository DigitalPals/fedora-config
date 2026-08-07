import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Widgets
import "../Common"

PanelWindow {
    id: barWindow

    anchors {
        top: Settings.position === "top"
        bottom: Settings.position === "bottom"
        left: true
        right: true
    }
    readonly property int layoutMode: width >= Theme.breakpointWide ? 2
        : width >= Theme.breakpointMedium ? 1 : 0
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

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property int volume: sink && sink.audio ? Math.round(sink.audio.volume * 100) : 0
    readonly property bool sinkMuted: sink && sink.audio ? sink.audio.muted : false
    readonly property bool micMuted: source && source.audio ? source.audio.muted : false

    readonly property var battery: UPower.displayDevice
    readonly property real batteryPct: battery ? (battery.percentage <= 1 ? battery.percentage * 100 : battery.percentage) : 0
    readonly property bool charging: battery && (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.PendingCharge || battery.state === UPowerDeviceState.FullyCharged)

    readonly property var wifiDevice: {
        const devs = Networking.devices.values;
        return devs.find(d => d.networks !== undefined) ?? null;
    }
    readonly property var wifiActive: wifiDevice ? (wifiDevice.networks.values.find(n => n.connected) ?? null) : null

    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool btConnected: btAdapter !== null && btAdapter.devices.values.some(d => d.connected)

    readonly property var player: {
        const ps = Mpris.players.values;
        return ps.find(p => p.isPlaying) ?? ps.find(p => p.playbackState === MprisPlaybackState.Paused) ?? (ps.length > 0 ? ps[0] : null);
    }
    readonly property bool mediaVisible: player !== null && player.trackTitle !== ""

    function playerGlyph(p) {
        if (!p)
            return "";
        const id = (p.identity + " " + p.desktopEntry).toLowerCase();
        if (id.includes("spotify"))
            return "";
        if (id.includes("firefox") || id.includes("zen"))
            return "";
        if (id.includes("chromium") || id.includes("chrome") || id.includes("brave"))
            return "";
        if (id.includes("edge"))
            return "";
        if (id.includes("youtube"))
            return "";
        if (id.includes("mpv") || id.includes("vlc") || id.includes("video"))
            return "";
        return "";
    }

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
        case "media": return mediaVisible;
        case "bt": return btConnected;
        case "batt": return battery !== null && battery.isLaptopBattery;
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

    function moduleForPanel(name) {
        const item = panelAnchors[name];
        return item && item.visible ? item : null;
    }

    // A module disabled from the settings window takes its open popout with
    // it; callLater lets the Repeater rebuild settle first.
    Connections {
        target: Settings

        function onModsChanged() {
            if (!Popouts.open || Popouts.currentName === "settings")
                return;
            Qt.callLater(() => {
                if (Popouts.open && !barWindow.moduleForPanel(Popouts.currentName))
                    Popouts.close();
            });
        }
    }

    readonly property var moduleComponents: ({
        ws: cmpWs, media: cmpMedia, clock: cmpClock, weather: cmpWeather,
        t3: cmpT3, vol: cmpVol, wifi: cmpWifi, batt: cmpBatt, bell: cmpBell, bt: cmpBt,
        idle: cmpIdle, control: cmpControl
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

        anchors.verticalCenter: parent.verticalCenter
        active: modelData.on && barWindow.autoRule(modelData.id)
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
        }
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
                if (Popouts.currentName === "settings") {
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
        anchors.fill: parent
        z: 100

        HoverHandler {
            id: barHover
            blocking: false

            onPointChanged: barWindow.hoverPanelAt(point.position)

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

            Repeater {
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

                    Component.onCompleted: barWindow.registerPanel("media", mediaChip)
                    Component.onDestruction: barWindow.unregisterPanel("media", mediaChip)

                    Divider {
                        visible: mediaModule.dividerBefore
                    }

            Rectangle {
                id: mediaChip
                visible: barWindow.mediaVisible
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: mediaRow.implicitWidth + 14
                implicitHeight: Theme.chipHeight
                radius: Theme.chipRadius
                color: barWindow.popoutOpen("media") ? Theme.hoverFillStrong : mediaMouse.containsMouse ? Theme.hoverFill : "transparent"

                Row {
                    id: mediaRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: barWindow.playerGlyph(barWindow.player)
                        font.family: Theme.fontIcon
                        font.pixelSize: Theme.barIconSize
                        color: barWindow.popoutOpen("media") || mediaMouse.containsMouse ? Theme.textHi : Theme.icon
                    }

                    Text {
                        visible: barWindow.layoutMode > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (!barWindow.player)
                                return "";
                            const artist = barWindow.player.trackArtist;
                            return barWindow.player.trackTitle + (artist ? " — " + artist : "");
                        }
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.barTextSize
                        color: barWindow.popoutOpen("media") || mediaMouse.containsMouse ? Theme.textHi : Theme.textMid
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, barWindow.layoutMode >= 2
                            ? Theme.mediaTitleWideWidth : Theme.mediaTitleMediumWidth)
                    }
                }

                MouseArea {
                    id: mediaMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: barWindow.hoverOpen("media", mediaModule.isle, mediaChip)
                    onPositionChanged: barWindow.hoverOpen("media", mediaModule.isle, mediaChip)
                    onExited: barWindow.cancelHover("media")
                    onClicked: barWindow.togglePopout("media", mediaModule.isle, mediaChip)
                }

                BarTooltip {
                    hovered: mediaMouse.containsMouse
                    text: barWindow.player ? barWindow.player.trackTitle : "Media"
                    y: parent.height + 6
                    x: (parent.width - width) / 2
                }
            }
                }
            }
        }

        // CENTER — clock + weather
        Cluster {
            id: centerCluster
            anchors.horizontalCenter: parent.horizontalCenter
            padding: 5
            spacing: 3

            Repeater {
                model: Settings.mods.center
                delegate: ModuleSlot { col: "center"; colList: Settings.mods.center }
            }

            Component {
                id: cmpClock

            Rectangle {
                id: clockChip
                property string isle: "center"

                Component.onCompleted: barWindow.registerPanel("calendar", clockChip)
                Component.onDestruction: barWindow.unregisterPanel("calendar", clockChip)
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: clockRow.implicitWidth + 14
                implicitHeight: Theme.chipHeight
                radius: Theme.chipRadius
                color: barWindow.popoutOpen("calendar") ? Theme.hoverFillStrong : clockMouse.containsMouse ? Theme.hoverFill : "transparent"

                Row {
                    id: clockRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDateTime(clock.date, Settings.clock24 ? "HH:mm" : "h:mm AP")
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.barTextSize
                        font.weight: Theme.weightSemibold
                        font.features: Theme.tabularNumberFeatures
                        color: Theme.textHi
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDateTime(clock.date, "ddd dd")
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.barTextSize
                        font.features: Theme.tabularNumberFeatures
                        color: barWindow.popoutOpen("calendar") || clockMouse.containsMouse ? Theme.textMid : Theme.textLow
                    }
                }

                MouseArea {
                    id: clockMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: barWindow.hoverOpen("calendar", clockChip.isle, clockChip)
                    onPositionChanged: barWindow.hoverOpen("calendar", clockChip.isle, clockChip)
                    onExited: barWindow.cancelHover("calendar")
                    onClicked: barWindow.togglePopout("calendar", clockChip.isle, clockChip)
                }

                BarTooltip {
                    hovered: clockMouse.containsMouse
                    text: Qt.formatDateTime(clock.date, "dddd, MMMM d")
                    y: parent.height + 6
                    x: (parent.width - width) / 2
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
                    visible: Weather.ready

                    Component.onCompleted: barWindow.registerPanel("weather", weatherChip)
                    Component.onDestruction: barWindow.unregisterPanel("weather", weatherChip)

                    Divider {
                        visible: weatherModule.dividerBefore && Weather.ready
                    }

            // Quiet weather chip next to the clock (design 1g).
            Rectangle {
                id: weatherChip
                visible: Weather.ready
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: weatherRow.implicitWidth + 12
                implicitHeight: Theme.chipHeight
                radius: Theme.chipRadius
                color: barWindow.popoutOpen("weather") ? Theme.hoverFillStrong : weatherMouse.containsMouse ? Theme.hoverFill : "transparent"

                Row {
                    id: weatherRow
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.glyph(Weather.code, Weather.isDay)
                        font.family: Theme.fontIcon
                        font.pixelSize: Theme.barIconSize
                        color: Weather.glyphColor(Weather.code, Weather.isDay)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.temp + "°"
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.barTextSize
                        font.weight: Theme.weightSemibold
                        font.features: Theme.tabularNumberFeatures
                        color: Theme.textMid
                    }

                    Text {
                        visible: barWindow.layoutMode >= 1
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.condition
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.barTextSize
                        color: barWindow.popoutOpen("weather") || weatherMouse.containsMouse ? Theme.textMid : Theme.textLow
                    }
                }

                MouseArea {
                    id: weatherMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: barWindow.hoverOpen("weather", weatherModule.isle, weatherChip)
                    onPositionChanged: barWindow.hoverOpen("weather", weatherModule.isle, weatherChip)
                    onExited: barWindow.cancelHover("weather")
                    onClicked: barWindow.togglePopout("weather", weatherModule.isle, weatherChip)
                }

                BarTooltip {
                    hovered: weatherMouse.containsMouse
                    text: Weather.place + " · " + Weather.condition
                    y: parent.height + 6
                    x: (parent.width - width) / 2
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

            Repeater {
                model: Settings.mods.right
                delegate: ModuleSlot { col: "right"; colList: Settings.mods.right }
            }

            // T3 + model usage travel as one module: the chips share the AI
            // corner and their internal divider (design v2 "T3 usage chips").
            Component {
                id: cmpT3

                Row {
                    id: t3Row

                    property string isle: "right"
                    property bool dividerBefore: false
                    property bool dividerAfter: false
                    spacing: 1

                    Component.onCompleted: {
                        barWindow.registerPanel("t3code", t3Chip);
                        barWindow.registerPanel("usage", usageChips);
                    }
                    Component.onDestruction: {
                        barWindow.unregisterPanel("t3code", t3Chip);
                        barWindow.unregisterPanel("usage", usageChips);
                    }

                    Divider {
                        visible: t3Row.dividerBefore
                    }

            T3Chip {
                id: t3Chip
                displayMode: barWindow.layoutMode
                held: barWindow.popoutOpen("t3code")
                onClicked: barWindow.togglePopout("t3code", t3Row.isle, t3Chip)
                onEntered: barWindow.hoverOpen("t3code", t3Row.isle, t3Chip)
                onExited: barWindow.cancelHover("t3code")
            }

            Divider {}

            // Anchored as one module rather than per provider chip: the
            // panel should not slide sideways as hover-through switches
            // between providers.
            UsageChips {
                id: usageChips
                displayMode: barWindow.layoutMode
                held: barWindow.popoutOpen("usage")
                onChipClicked: key => {
                    if (barWindow.popoutOpen("usage") && Usage.selected === key) {
                        Popouts.close();
                    } else {
                        Usage.selected = key;
                        Popouts.openPanel("usage", t3Row.isle, barWindow.anchorOf(usageChips));
                    }
                }
                onChipEntered: key => {
                    // Hover-through: with any popout open, hovering a chip
                    // shows that provider's usage view (design 1d).
                    if (Popouts.open)
                        Usage.selected = key;
                    barWindow.hoverOpen("usage", t3Row.isle, usageChips);
                }
                onChipExited: barWindow.cancelHover("usage")
            }

                    Divider {
                        visible: t3Row.dividerAfter
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
                glyph: barWindow.sinkMuted || barWindow.volume === 0 ? "" : barWindow.volume < 50 ? "" : ""
                label: barWindow.layoutMode === 0 ? "" : barWindow.volume + "%"
                held: barWindow.popoutOpen("audio")
                alert: barWindow.sinkMuted
                tooltip: "Audio · wheel volume · middle mute"
                tooltipAlign: 1
                onClicked: barWindow.togglePopout("audio", audioIcon.isle, audioIcon)
                onMiddleClicked: {
                    if (barWindow.sink && barWindow.sink.audio)
                        barWindow.sink.audio.muted = !barWindow.sink.audio.muted;
                }
                onWheeled: steps => {
                    if (barWindow.sink && barWindow.sink.audio)
                        barWindow.sink.audio.volume = Math.max(0, Math.min(1, barWindow.sink.audio.volume + steps * 0.05));
                }
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
                idleColor: Networking.wifiEnabled ? (barWindow.wifiActive !== null ? Theme.icon : Theme.textLow) : Theme.textFaint
                tooltip: barWindow.wifiActive ? "Wi-Fi · " + barWindow.wifiActive.name : "Wi-Fi"
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
                visible: barWindow.btConnected
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
                visible: barWindow.battery !== null && barWindow.battery.isLaptopBattery
                // md-battery_high / md-battery_charging_high. The charging
                // glyph carries its own bolt, so nothing is overlaid; it is
                // also wider, hence the fixed column below — 13.5 is what
                // the previous Font Awesome glyph laid out at, so the rest
                // of the cluster keeps its position.
                glyph: barWindow.charging ? "󱊦" : "󱊣"
                glyphWidth: 13.5
                label: barWindow.layoutMode === 0 ? "" : Math.round(barWindow.batteryPct) + "%"
                alert: !barWindow.charging && barWindow.batteryPct <= 10
                held: barWindow.popoutOpen("battery")
                idleColor: barWindow.charging ? Theme.accent : barWindow.batteryPct <= 20 && !barWindow.charging ? Theme.amber : Theme.icon
                tooltip: "Battery " + Math.round(barWindow.batteryPct) + "%" + (barWindow.charging ? " · charging" : "")
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
                    visible: Notifs.count > 0
                    anchors.top: bellIcon.top
                    anchors.topMargin: -1
                    anchors.right: bellIcon.right
                    anchors.rightMargin: 3
                    width: 10
                    height: 10
                    radius: 5
                    color: Theme.barBg

                    Rectangle {
                        anchors.centerIn: parent
                        width: 6
                        height: 6
                        radius: 3
                        color: Notifs.hasUrgent ? Theme.red : Theme.accent
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

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
