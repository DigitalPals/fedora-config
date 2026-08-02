import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import "../Common"

// Control Center (design t5): quick toggles with an inline wallpaper
// expander, sliders, battery + power profile, session actions. Lives as
// a connected popout fused to the left island; the Wi-Fi and Bluetooth
// chevrons morph this surface to the detail views in place.
Surface {
    id: root

    implicitWidth: 440

    property bool wpOpen: false

    function wpName(path) {
        return path.split("/").pop().replace(/\.[^.]+$/, "");
    }

    readonly property var wifiDevice: Networking.devices.values.find(d => d.networks !== undefined) ?? null
    readonly property var wifiActive: wifiDevice ? (wifiDevice.networks.values.find(n => n.connected) ?? null) : null
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var btConnected: btAdapter !== null && btAdapter.enabled ? (Bluetooth.devices.values.find(d => d.connected) ?? null) : null

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool micMuted: source && source.audio ? source.audio.muted : false

    readonly property var battery: UPower.displayDevice
    readonly property real pct: battery ? (battery.percentage <= 1 ? battery.percentage * 100 : battery.percentage) : 0
    readonly property bool charging: battery && (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.PendingCharge)
    readonly property bool full: battery && battery.state === UPowerDeviceState.FullyCharged

    readonly property string lockCmd: "hyprlock --config " + Quickshell.env("HOME") + "/.config/hypr/hyprlock.conf --immediate-render --no-fade-in"

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    function run(cmd) {
        Quickshell.execDetached(["sh", "-c", cmd]);
        Popouts.close();
    }

    function fmtDuration(secs) {
        if (!secs || secs <= 0)
            return "";
        const h = Math.floor(secs / 3600);
        const m = Math.round((secs % 3600) / 60);
        return h > 0 ? `${h} h ${String(m).padStart(2, "0")} m` : `${m} m`;
    }

    // Quick-toggle tile
    component Tile: Rectangle {
        id: tile

        property string glyph: ""
        property string iconSource: ""
        property string title
        property string subtitle
        property bool on: false
        property bool alert: false
        property bool chevron: false
        signal toggled
        signal expanded

        width: (root.width - 16 - 4 - 6) / 2
        height: 46
        radius: 10
        color: alert ? (tileMouse.containsMouse ? Qt.rgba(232 / 255, 131 / 255, 122 / 255, 0.2) : Qt.rgba(232 / 255, 131 / 255, 122 / 255, 0.12))
             : on ? (tileMouse.containsMouse ? Qt.rgba(158 / 255, 203 / 255, 235 / 255, 0.2) : Qt.rgba(158 / 255, 203 / 255, 235 / 255, 0.14))
             : (tileMouse.containsMouse ? Theme.hoverFillStrong : Theme.cardFill)

        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 12
            spacing: 10

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18

                Text {
                    visible: tile.glyph !== ""
                    anchors.centerIn: parent
                    text: tile.glyph
                    font.family: Theme.fontIcon
                    font.pixelSize: 14
                    color: tile.alert ? Theme.redText : tile.on ? Theme.accent : Theme.textLow
                }

                Image {
                    visible: tile.iconSource !== ""
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    sourceSize: Qt.size(28, 28)
                    source: tile.iconSource
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: tile.width - 62 - (tile.chevron ? 18 : 0)
                spacing: 1

                Text {
                    width: parent.width
                    text: tile.title
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight: 500
                    color: tile.alert ? Theme.redText : tile.on ? Theme.textHi : Theme.textMid
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: tile.subtitle
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    color: tile.on || tile.alert ? Theme.textLow : Theme.textDim
                    elide: Text.ElideRight
                }
            }
        }

        Text {
            visible: tile.chevron
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "\uf054"
            font.family: Theme.fontIcon
            font.pixelSize: 9
            color: chevMouse.containsMouse ? Theme.textHi : Theme.textDim

            MouseArea {
                id: chevMouse
                anchors.fill: parent
                anchors.margins: -8
                hoverEnabled: true
                onClicked: tile.expanded()
            }
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            anchors.rightMargin: tile.chevron ? 30 : 0
            hoverEnabled: true
            onClicked: tile.toggled()
        }
    }

    // ---- Header -----------------------------------------------------
    Item {
        width: parent.width
        height: 46

        Row {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf30a"
                font.family: Theme.fontIcon
                font.pixelSize: 16
                color: Theme.textMid
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    text: SysInfo.user + "@" + SysInfo.host
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    font.weight: 600
                    color: Theme.textHi
                }

                Text {
                    text: "up " + SysInfo.uptime + " · linux " + SysInfo.kernel
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    color: Theme.textDim
                }
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 24
            radius: Theme.chipRadius
            color: gearMouse.containsMouse ? Theme.hoverFillStrong : "transparent"

            Text {
                anchors.centerIn: parent
                text: "\uf013"
                font.family: Theme.fontIcon
                font.pixelSize: 12
                color: gearMouse.containsMouse ? Theme.textHi : Theme.textLow
            }

            MouseArea {
                id: gearMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.run("gnome-control-center")
            }
        }
    }

    // ---- Quick toggles ---------------------------------------------
    Grid {
        columns: 2
        columnSpacing: 6
        rowSpacing: 6
        width: parent.width - 4
        x: 2

        Tile {
            glyph: "\uf1eb"
            title: "Wi-Fi"
            subtitle: Networking.wifiEnabled ? (root.wifiActive ? root.wifiActive.name : "On") : "Off"
            on: Networking.wifiEnabled
            chevron: true
            onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
            onExpanded: Popouts.openPanel("wifi", "left")
        }

        Tile {
            glyph: "\uf293"
            title: "Bluetooth"
            subtitle: {
                if (root.btAdapter === null || !root.btAdapter.enabled)
                    return "Off";
                if (root.btConnected)
                    return root.btConnected.deviceName + (root.btConnected.batteryAvailable ? " · " + Math.round(root.btConnected.battery * 100) + "%" : "");
                return "On";
            }
            on: root.btAdapter !== null && root.btAdapter.enabled
            chevron: true
            onToggled: {
                if (root.btAdapter)
                    root.btAdapter.enabled = !root.btAdapter.enabled;
            }
            onExpanded: Popouts.openPanel("bluetooth", "left")
        }

        Tile {
            iconSource: Quickshell.shellDir + "/assets/tailscale" + (SysInfo.tsRunning ? "" : "-dim") + ".svg"
            title: "Tailscale"
            subtitle: SysInfo.tsRunning ? SysInfo.tsNet : "Stopped"
            on: SysInfo.tsRunning
            chevron: true
            onToggled: {
                Quickshell.execDetached(["sh", "-c", SysInfo.tsRunning ? "tailscale down" : "tailscale up"]);
                tsRefresh.restart();
            }
            onExpanded: root.run("xdg-open https://login.tailscale.com/admin/machines")
        }

        Tile {
            glyph: "\uf0f4"
            title: "Idle inhibit"
            subtitle: SysInfo.idleInhibited ? "Display stays awake" : "Off"
            on: SysInfo.idleInhibited
            onToggled: SysInfo.idleInhibited = !SysInfo.idleInhibited
        }

        Tile {
            glyph: "\uf1f6"
            title: "Do Not Disturb"
            subtitle: Notifs.dnd ? "On" : "Off"
            on: Notifs.dnd
            onToggled: Notifs.dnd = !Notifs.dnd
        }

        Tile {
            glyph: root.micMuted ? "\uf131" : "\uf130"
            title: "Microphone"
            subtitle: root.micMuted ? "Muted · click to unmute" : "On · click to mute"
            alert: root.micMuted
            onToggled: {
                if (root.source && root.source.audio)
                    root.source.audio.muted = !root.source.audio.muted;
            }
        }

        Tile {
            glyph: "\uf03e"
            title: "Wallpaper"
            subtitle: Wallpaper.current !== "" ? root.wpName(Wallpaper.current) : "None"
            chevron: true
            onToggled: root.wpOpen = !root.wpOpen
            onExpanded: root.wpOpen = !root.wpOpen
        }
    }

    // Inline wallpaper expander (t5): collapses to zero height, reveals a
    // three-column grid of choices below the toggle grid.
    Item {
        width: parent.width - 4
        x: 2
        height: root.wpOpen ? wpGrid.implicitHeight + 8 : 0
        clip: true

        Grid {
            id: wpGrid
            y: 8
            columns: 3
            columnSpacing: 6
            rowSpacing: 6
            width: parent.width

            Repeater {
                model: Wallpaper.files.slice(0, 6)

                delegate: Rectangle {
                    required property string modelData
                    readonly property bool current: Wallpaper.current === modelData

                    width: (root.width - 16 - 4 - 12) / 3
                    height: 68
                    radius: Theme.rowRadius
                    color: "transparent"
                    border.width: current ? 2 : 1
                    border.color: current ? Theme.accent : wpMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Theme.hairlineSoft

                    ClippingRectangle {
                        x: 3
                        y: 3
                        width: parent.width - 6
                        height: 44
                        radius: Theme.chipRadius
                        color: Theme.cardFill

                        Image {
                            anchors.fill: parent
                            source: modelData
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(160, 100)
                            asynchronous: true
                        }
                    }

                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 10
                        horizontalAlignment: Text.AlignHCenter
                        text: root.wpName(modelData)
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        font.weight: 500
                        color: current ? Theme.textMid : Theme.textLow
                        elide: Text.ElideMiddle
                    }

                    MouseArea {
                        id: wpMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Wallpaper.set(modelData)
                    }
                }
            }

            Rectangle {
                width: (root.width - 16 - 4 - 12) / 3
                height: 68
                radius: Theme.rowRadius
                color: shufMouse.containsMouse ? Theme.hoverFillStrong : Theme.cardFill

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "\uf074"
                        font.family: Theme.fontIcon
                        font.pixelSize: 13
                        color: shufMouse.containsMouse ? Theme.textHi : Theme.textLow
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Shuffle"
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        font.weight: 500
                        color: shufMouse.containsMouse ? Theme.textHi : Theme.textLow
                    }
                }

                MouseArea {
                    id: shufMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Wallpaper.shuffle()
                }
            }
        }
    }

    Timer {
        id: tsRefresh
        interval: 1200
        onTriggered: SysInfo.refreshTailscale()
    }

    HDivider {}

    // ---- Sliders ----------------------------------------------------
    Row {
        width: parent.width
        leftPadding: 10
        rightPadding: 10
        topPadding: 2
        spacing: 10

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            horizontalAlignment: Text.AlignHCenter
            text: root.sink && root.sink.audio && root.sink.audio.muted ? "\uf026" : "\uf028"
            font.family: Theme.fontIcon
            font.pixelSize: 13
            color: Theme.textMid

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (root.sink && root.sink.audio)
                        root.sink.audio.muted = !root.sink.audio.muted;
                }
            }
        }

        HSlider {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 84
            value: root.sink && root.sink.audio ? root.sink.audio.volume : 0
            onMoved: v => {
                if (root.sink && root.sink.audio)
                    root.sink.audio.volume = v;
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            horizontalAlignment: Text.AlignRight
            text: root.sink && root.sink.audio ? Math.round(root.sink.audio.volume * 100) : "--"
            font.family: Theme.fontMono
            font.pixelSize: 11
            font.weight: 500
            color: Theme.textLow
        }
    }

    Row {
        width: parent.width
        leftPadding: 10
        rightPadding: 10
        topPadding: 8
        spacing: 10

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            horizontalAlignment: Text.AlignHCenter
            text: root.micMuted ? "\uf131" : "\uf130"
            font.family: Theme.fontIcon
            font.pixelSize: 13
            color: root.micMuted ? Theme.redText : Theme.textMid

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (root.source && root.source.audio)
                        root.source.audio.muted = !root.source.audio.muted;
                }
            }
        }

        HSlider {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 84
            dimmed: root.micMuted
            value: root.source && root.source.audio ? root.source.audio.volume : 0
            onMoved: v => {
                if (root.source && root.source.audio)
                    root.source.audio.volume = v;
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            horizontalAlignment: Text.AlignRight
            text: root.source && root.source.audio ? Math.round(root.source.audio.volume * 100) : "--"
            font.family: Theme.fontMono
            font.pixelSize: 11
            font.weight: 500
            color: root.micMuted ? Theme.textDim : Theme.textLow
        }
    }

    HDivider {
        visible: root.battery !== null && root.battery.isLaptopBattery
    }

    // ---- Battery + power profile ------------------------------------
    Item {
        visible: root.battery !== null && root.battery.isLaptopBattery
        width: parent.width
        height: 32

        Row {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.charging || root.full ? "\uf0e7" : "\uf240"
                font.family: Theme.fontIcon
                font.pixelSize: 12
                color: root.pct <= 10 && !root.charging ? Theme.redText : Theme.accent
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    let s = Math.round(root.pct) + "%";
                    if (root.charging && root.battery.timeToFull > 0)
                        s += " · " + root.fmtDuration(root.battery.timeToFull) + " to full";
                    else if (!root.charging && !root.full && root.battery.timeToEmpty > 0)
                        s += " · " + root.fmtDuration(root.battery.timeToEmpty) + " left";
                    else if (root.full)
                        s += " · fully charged";
                    return s;
                }
                font.family: Theme.fontSans
                font.pixelSize: 12
                font.weight: 500
                color: Theme.textMid
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Repeater {
                model: [
                    { label: "Saver", profile: PowerProfile.PowerSaver, available: true },
                    { label: "Balanced", profile: PowerProfile.Balanced, available: true },
                    { label: "Perf", profile: PowerProfile.Performance, available: PowerProfiles.hasPerformanceProfile }
                ]

                delegate: Rectangle {
                    required property var modelData
                    readonly property bool current: PowerProfiles.profile === modelData.profile

                    visible: modelData.available
                    width: profText.implicitWidth + 18
                    height: 22
                    radius: Theme.chipRadius
                    color: current ? Theme.accent : profMouse.containsMouse ? Theme.hoverFillStrong : Theme.cardFill

                    Text {
                        id: profText
                        anchors.centerIn: parent
                        text: parent.modelData.label
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        font.weight: parent.current ? 600 : 500
                        color: parent.current ? Theme.accentFg : profMouse.containsMouse ? Theme.textHi : Theme.textLow
                    }

                    MouseArea {
                        id: profMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: PowerProfiles.profile = parent.modelData.profile
                    }
                }
            }
        }
    }

    HDivider {}

    // ---- Session ----------------------------------------------------
    Row {
        width: parent.width - 4
        x: 2
        spacing: 6

        Repeater {
            model: [
                { glyph: "\uf023", label: "Lock", danger: false, cmd: root.lockCmd },
                { glyph: "\uf186", label: "Suspend", danger: false, cmd: "systemctl suspend" },
                { glyph: "\uf021", label: "Reboot", danger: false, cmd: "systemctl reboot" },
                { glyph: "\uf011", label: "Shut down", danger: true, cmd: "systemctl poweroff" }
            ]

            delegate: Rectangle {
                required property var modelData

                width: (root.width - 16 - 4 - 18) / 4
                height: 58
                radius: 10
                color: modelData.danger
                    ? (sessMouse.containsMouse ? Qt.rgba(232 / 255, 131 / 255, 122 / 255, 0.18) : Qt.rgba(232 / 255, 131 / 255, 122 / 255, 0.10))
                    : (sessMouse.containsMouse ? Theme.hoverFillStrong : Theme.cardFill)

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.glyph
                        font.family: Theme.fontIcon
                        font.pixelSize: 15
                        color: modelData.danger ? Theme.redText : Theme.textMid
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.label
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: 500
                        color: modelData.danger ? Theme.redText : Theme.textLow
                    }
                }

                MouseArea {
                    id: sessMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.run(parent.modelData.cmd)
                }
            }
        }
    }

    // ---- Footer -----------------------------------------------------
    Item {
        width: parent.width
        height: 26

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Toggles: click = toggle · chevron = expand"
            font.family: Theme.fontSans
            font.pixelSize: 11
            color: Theme.textDim
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "esc to close"
            font.family: Theme.fontMono
            font.pixelSize: 11
            font.weight: 500
            color: Theme.textDim
        }
    }
}
