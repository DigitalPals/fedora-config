import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
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
        top: true
        left: true
        right: true
    }
    // Tall stable surface: the bar strip at the top plus room for the
    // connected popouts. The native window never animates; only items
    // inside it do. Input is masked to the bar strip + open popout.
    implicitHeight: 760
    // Balanced spacing: with Hyprland's gaps_out (10) on top of the
    // exclusive zone, windows end up exactly barTopMargin (8) below the
    // bar's bottom edge — the same gap as above the bar.
    exclusiveZone: Theme.barTopMargin + Theme.barHeight - 2
    color: "transparent"

    mask: Region {
        item: barStrip

        regions: [
            Region {
                item: leftPopout.maskItem
            },
            Region {
                item: centerPopout.maskItem
            },
            Region {
                item: rightPopout.maskItem
            }
        ]
    }

    WlrLayershell.keyboardFocus: Popouts.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    HyprlandFocusGrab {
        active: Popouts.open
        windows: [barWindow]
        onCleared: Popouts.close()
    }

    IpcHandler {
        target: "popouts"

        function toggle(name: string): void {
            Popouts.toggle(name);
        }

        function close(): void {
            Popouts.close();
        }
    }

    // ---- shared service state ----------------------------------------

    IdleInhibitor {
        window: barWindow
        enabled: SysInfo.idleInhibited
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

    function batteryGlyph(pct) {
        if (pct <= 12)
            return "";
        if (pct <= 37)
            return "";
        if (pct <= 62)
            return "";
        if (pct <= 87)
            return "";
        return "";
    }

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

    // Hover-to-open (caelestia): once a popout is open, hovering another
    // module switches straight to its popout — no click needed until the
    // popout is dismissed again.
    function hoverOpen(name, isle) {
        if (Popouts.open && Popouts.currentName !== name)
            Popouts.openPanel(name, isle);
    }

    // Input region for the bar strip itself.
    Item {
        id: barStrip
        x: 0
        y: 0
        width: parent.width
        height: Theme.barTopMargin + Theme.barHeight + 4
    }

    // One continuous menubar slab behind all three sections, rendered
    // beneath the popout surfaces so its shadow never falls on an open
    // panel.
    Item {
        anchors.fill: parent
        anchors.topMargin: Theme.barTopMargin
        anchors.leftMargin: Theme.barSideMargin
        anchors.rightMargin: Theme.barSideMargin

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
    }

    // ---- connected popouts (design t5) --------------------------------
    // One popout surface per section, fused to the bar slab's bottom
    // edge and rendered under the cluster contents.

    IslandPopout {
        id: leftPopout
        island: leftCluster
        isle: "left"
    }

    IslandPopout {
        id: centerPopout
        island: centerCluster
        isle: "center"
    }

    IslandPopout {
        id: rightPopout
        island: rightCluster
        isle: "right"
    }

    // ---- layout ------------------------------------------------------

    Item {
        anchors.fill: parent
        anchors.topMargin: Theme.barTopMargin
        anchors.leftMargin: Theme.barSideMargin
        anchors.rightMargin: Theme.barSideMargin

        // LEFT — workspaces
        Cluster {
            id: leftCluster
            anchors.left: parent.left
            padding: 6
            spacing: 2

            Workspaces {}
        }

        // CENTER — clock + media
        Cluster {
            id: centerCluster
            anchors.horizontalCenter: parent.horizontalCenter
            padding: 6
            spacing: 4

            Rectangle {
                id: clockChip
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: clockRow.implicitWidth + 18
                implicitHeight: 26
                radius: Theme.chipRadius
                color: barWindow.popoutOpen("calendar") ? Theme.hoverFillStrong : clockMouse.containsMouse ? Theme.hoverFill : "transparent"

                Row {
                    id: clockRow
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        font.family: Theme.fontMono
                        font.pixelSize: 13
                        font.weight: 600
                        color: Theme.textHi
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDateTime(clock.date, "ddd MMM d")
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                        color: barWindow.popoutOpen("calendar") || clockMouse.containsMouse ? Theme.textMid : Theme.textLow
                    }
                }

                MouseArea {
                    id: clockMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: barWindow.hoverOpen("calendar", "center")
                    onClicked: Popouts.toggle("calendar", "center")
                }
            }

            Divider {
                visible: barWindow.mediaVisible
            }

            Rectangle {
                id: mediaChip
                visible: barWindow.mediaVisible
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: mediaRow.implicitWidth + 18
                implicitHeight: 26
                radius: Theme.chipRadius
                color: barWindow.popoutOpen("media") ? Theme.hoverFillStrong : mediaMouse.containsMouse ? Theme.hoverFill : "transparent"

                Row {
                    id: mediaRow
                    anchors.centerIn: parent
                    spacing: 7

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: barWindow.playerGlyph(barWindow.player)
                        font.family: Theme.fontIcon
                        font.pixelSize: 13
                        color: barWindow.popoutOpen("media") || mediaMouse.containsMouse ? Theme.textHi : Theme.icon
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (!barWindow.player)
                                return "";
                            const artist = barWindow.player.trackArtist;
                            return barWindow.player.trackTitle + (artist ? " — " + artist : "");
                        }
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                        color: barWindow.popoutOpen("media") || mediaMouse.containsMouse ? Theme.textHi : Theme.textMid
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 190)
                    }
                }

                MouseArea {
                    id: mediaMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: barWindow.hoverOpen("media", "center")
                    onClicked: Popouts.toggle("media", "center")
                }
            }
        }

        // RIGHT — model usage + audio + status modules + Control Center
        Cluster {
            id: rightCluster
            anchors.right: parent.right
            padding: 8
            spacing: 1

            UsageChips {
                held: barWindow.popoutOpen("usage")
                onClicked: Popouts.toggle("usage", "right")
                onEntered: barWindow.hoverOpen("usage", "right")
            }

            Divider {}

            BarIcon {
                glyph: ""
                active: SysInfo.idleInhibited
                idleColor: Theme.textLow
                onClicked: SysInfo.idleInhibited = !SysInfo.idleInhibited
            }

            BarIcon {
                glyph: ""
                held: barWindow.popoutOpen("wifi")
                idleColor: Networking.wifiEnabled ? (barWindow.wifiActive !== null ? Theme.icon : Theme.textLow) : Theme.textFaint
                onClicked: Popouts.toggle("wifi", "right")
                onEntered: barWindow.hoverOpen("wifi", "right")
            }

            BarIcon {
                glyph: barWindow.batteryGlyph(barWindow.batteryPct)
                label: "" + Math.round(barWindow.batteryPct)
                alert: !barWindow.charging && barWindow.batteryPct <= 10
                held: barWindow.popoutOpen("battery")
                idleColor: barWindow.charging ? Theme.accent : barWindow.batteryPct <= 20 && !barWindow.charging ? Theme.amber : Theme.icon
                visible: barWindow.battery !== null && barWindow.battery.isLaptopBattery
                onClicked: Popouts.toggle("battery", "right")
                onEntered: barWindow.hoverOpen("battery", "right")
            }

            Item {
                width: bellIcon.width
                height: Theme.barHeight
                anchors.verticalCenter: parent.verticalCenter

                BarIcon {
                    id: bellIcon
                    glyph: ""
                    held: barWindow.popoutOpen("notifications")
                    onClicked: Popouts.toggle("notifications", "right")
                    onEntered: barWindow.hoverOpen("notifications", "right")
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

            Divider {}

            BarIcon {
                glyph: "" // fedora
                glyphSize: 15
                hPadding: 9
                active: barWindow.popoutOpen("control")
                onClicked: Popouts.toggle("control", "right")
                onEntered: barWindow.hoverOpen("control", "right")
            }
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
