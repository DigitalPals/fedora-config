pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../Common"

// Control Center ("QuickShell Menubar" redesign): two big radio tiles with
// in-place detail chevrons, a row of round quick toggles, the power-profile
// segmented pill, the design's filled brightness and volume sliders, the
// capture actions, the system stat cards, and the shell-settings footer.
Surface {
    id: root

    implicitWidth: Theme.popWidth
    padding: Theme.surfacePadding
    spacing: 12

    readonly property string binDir: Quickshell.env("HOME") + "/.local/bin/"
    readonly property var btConnected: BluetoothState.devices.filter(d => d.connected)

    // The stat cards and the Tailscale tile are live only while this panel
    // is on screen, so it says so rather than the singletons guessing from
    // Popouts. Keyed on `visible`, not construction: this panel is latched.
    Claim {
        active: root.visible
        onClaimed: {
            SysInfo.acquire();
            Tailscale.acquire();
            EthernetState.acquire();
        }
        onReleased: {
            SysInfo.release();
            Tailscale.release();
            EthernetState.release();
        }
    }

    function run(cmd) {
        Quickshell.execDetached(["sh", "-c", cmd]);
        Popouts.close();
    }

    // Big radio tile: round icon, name and status line, and a chevron that
    // morphs the surface to the detail view in place.
    component BigTile: Rectangle {
        id: tile

        property string glyph: ""
        property string title
        property string sub
        property bool on: false
        signal toggled
        signal expanded

        // Two settings with a value and a chevron each. Side by side as 64px
        // cards they were the heaviest thing in the panel and still had to
        // elide "Ethernet + …"; stacked as full-width rows they read as what
        // they are, in the same rhythm as every other row in the shell.
        width: parent ? parent.width : 0
        height: Theme.listRowHeight
        radius: Theme.chipRadius
        color: tileMouse.containsMouse ? Theme.chip : "transparent"
        scale: tileMouse.pressed ? 0.98 : 1

        Behavior on color {
            ColorAnimation { duration: Theme.surfaceDuration }
        }

        Behavior on scale {
            NumberAnimation {
                duration: Theme.pressDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.springCurve
            }
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton)
                    tile.expanded();
                else
                    tile.toggled();
            }
        }

        Item {
            id: tileMark
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.iconMedium
            height: Theme.iconMedium

            Sym {
                anchors.centerIn: parent
                name: tile.glyph
                size: Theme.iconMedium
                fill: tile.on ? 1 : 0
                color: tile.on ? Theme.accent : Theme.icon
            }
        }

        Text {
            id: tileTitle
            anchors.left: tileMark.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: tile.title
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontSecondary
            color: Theme.textHi
        }

        Text {
            anchors.left: tileTitle.right
            anchors.leftMargin: 8
            anchors.right: tileChevron.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: tile.sub
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontMicro
            color: tile.on ? Theme.textMid : Theme.textFaint
            elide: Text.ElideRight
        }

        Item {
            id: tileChevron
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.chipInnerHeight
            height: Theme.chipInnerHeight

            Sym {
                anchors.centerIn: parent
                name: "chevron_right"
                size: Theme.iconSmall
                symWeight: 450
                color: chevMouse.containsMouse ? Theme.textHi : Theme.textFaint
            }

            MouseArea {
                id: chevMouse
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: tile.expanded()
            }
        }
    }

    // Quick toggle: the menubar's own chip, lit on the accent container when
    // the thing is on, with its label underneath. Right-click opens the detail
    // view where one exists. It was a 46px circle; nothing else in the shell
    // is round, and five of them were the panel's dominant shape.
    component RoundToggle: Item {
        id: toggle

        property string glyph: ""
        property string iconSource: ""
        property string title
        property bool on: false
        property bool detail: false
        signal toggled
        signal expanded

        width: (root.width - 2 * root.padding - 4 * Theme.panelRowSpacing) / 5
        height: circle.height + 6 + toggleLabel.implicitHeight

        Rectangle {
            id: circle
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: parent.width
            height: Theme.listRowHeight
            radius: Theme.chipRadius
            color: toggle.on ? Theme.accentContainer
                : toggleMouse.containsMouse ? Theme.chipHover : Theme.chip
            // rest is the quiet chip; `on` is the only lit state
            scale: toggleMouse.pressed ? 0.95 : 1

            Behavior on color {
                ColorAnimation { duration: Theme.surfaceDuration }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: Theme.pressDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.springCurve
                }
            }

            Sym {
                visible: toggle.glyph !== ""
                anchors.centerIn: parent
                name: toggle.glyph
                size: Theme.iconMedium
                fill: toggle.on ? 1 : 0
                color: toggle.on ? Theme.accentContainerFg : Theme.icon
            }

            Image {
                visible: toggle.iconSource !== ""
                anchors.centerIn: parent
                width: Theme.iconMedium
                height: Theme.iconMedium
                sourceSize: Qt.size(40, 40)
                source: toggle.iconSource
            }
        }

        Text {
            id: toggleLabel
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: circle.bottom
            anchors.topMargin: 6
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: toggle.title
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontMicro
            font.weight: Theme.weightMedium
            color: toggle.on ? Theme.textMid : Theme.textFaint
        }

        MouseArea {
            id: toggleMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton && toggle.detail)
                    toggle.expanded();
                else
                    toggle.toggled();
            }
        }
    }

    // Small stat card for the CPU / RAM / TEMP row.
    component StatCard: Rectangle {
        id: stat

        property string label
        property string display
        property real fraction: 0
        property color tone: Theme.textHi
        property color barTone: Theme.accent

        width: (root.width - 2 * root.padding - 2 * Theme.panelSectionSpacing) / 3
        height: statCol.implicitHeight
        color: "transparent"

        Column {
            id: statCol
            width: parent.width
            spacing: 5

            Text {
                text: stat.label
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontMicro
                font.weight: Theme.weightSemibold
                font.letterSpacing: 1
                color: Theme.textFaint
            }

            Text {
                text: stat.display
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontBody
                font.weight: Theme.weightSemibold
                color: stat.tone
            }

            BlockMeter {
                width: parent.width
                height: 6
                blockWidth: 3
                gap: 2
                value: stat.fraction
                fillColor: stat.barTone
            }
        }
    }

    // ---- Radios ----------------------------------------------------------
    Column {
        width: parent.width
        spacing: Theme.panelRowSpacing

        BigTile {
            glyph: EthernetState.connected ? "lan"
                : WifiState.enabled ? "wifi" : "wifi_off"
            title: "Internet"
            sub: EthernetState.connected && WifiState.connected ? "Ethernet + Wi-Fi"
                : EthernetState.connected ? "Ethernet"
                : WifiState.connected ? WifiState.name
                : WifiState.enabled ? "No connection" : "Offline"
            on: EthernetState.connected || WifiState.connected
            onToggled: Popouts.openPanel("wifi", "right")
            onExpanded: Popouts.openPanel("wifi", "right")
        }

        BigTile {
            glyph: "bluetooth"
            title: "Bluetooth"
            sub: {
                if (!BluetoothState.enabled)
                    return "Off";
                if (root.btConnected.length === 0)
                    return "On";
                return root.btConnected[0].deviceName
                    + (root.btConnected.length > 1 ? " +" + (root.btConnected.length - 1) : "");
            }
            on: BluetoothState.enabled
            onToggled: Popouts.openPanel("bluetooth", "right")
            onExpanded: Popouts.openPanel("bluetooth", "right")
        }
    }

    // ---- Quick toggles ---------------------------------------------------
    Row {
        width: parent.width
        spacing: Theme.panelRowSpacing

        RoundToggle {
            glyph: "dark_mode"
            title: "Dark mode"
            on: Theme.dark
            onToggled: Settings.themeMode = Theme.dark ? "light" : "dark"
        }

        RoundToggle {
            glyph: "do_not_disturb_on"
            title: "Focus"
            on: Notifs.dnd
            onToggled: Notifs.setDnd(!Notifs.dnd)
        }

        RoundToggle {
            glyph: "nightlight"
            title: "Night light"
            on: SysInfo.nightLight
            onToggled: SysInfo.toggleNightLight()
        }

        RoundToggle {
            glyph: "coffee"
            title: "Idle inhibit"
            on: SysInfo.idleInhibited
            onToggled: SysInfo.toggleIdleInhibited()
        }

        RoundToggle {
            iconSource: Quickshell.shellDir + "/assets/tailscale" + (Tailscale.running ? "" : "-dim") + ".svg"
            title: "Tailscale"
            on: Tailscale.running
            detail: true
            onToggled: Tailscale.toggle()
            onExpanded: Popouts.openPanel("tailscale", "right")
        }
    }

    // ---- Power profile ---------------------------------------------------
    // Only where there is a profile daemon to talk to: on a machine without
    // power-profiles-daemon this row would be three buttons that do nothing.
    Item {
        visible: PowerProfiles.hasPerformanceProfile
        width: parent.width
        height: Theme.chipHeight

        Row {
            id: modeRow
            anchors.fill: parent
            anchors.margins: 5
            spacing: 4

            Repeater {
                model: [
                    { profile: PowerProfile.PowerSaver, glyph: "eco", label: "Saver" },
                    { profile: PowerProfile.Balanced, glyph: "balance", label: "Balanced" },
                    { profile: PowerProfile.Performance, glyph: "speed", label: "Performance" }
                ]

                delegate: Rectangle {
                    id: mode

                    required property var modelData
                    readonly property bool current: PowerProfiles.profile === modelData.profile

                    width: (modeRow.width - modeRow.spacing * 2) / 3
                    height: modeRow.height
                    radius: Theme.chipRadius
                    color: current ? Theme.chipHover
                        : modeMouse.containsMouse ? Theme.chip : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: Theme.chipFadeDuration }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Sym {
                            anchors.verticalCenter: parent.verticalCenter
                            name: mode.modelData.glyph
                            size: Theme.iconSmall + 2
                            fill: mode.current ? 1 : 0
                            color: mode.current ? Theme.textHi : Theme.textLow
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: mode.modelData.label
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontMicro
                            font.weight: Theme.weightMedium
                            font.letterSpacing: 0.2
                            color: mode.current ? Theme.textHi : Theme.textLow
                        }
                    }

                    MouseArea {
                        id: modeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: PowerProfiles.profile = mode.modelData.profile
                    }
                }
            }
        }
    }

    // ---- Brightness / volume ---------------------------------------------
    FillSlider {
        width: parent.width
        glyph: "sunny"
        accessibleName: "Brightness"
        value: Math.max(0, SysInfo.brightness) / 100
        ready: SysInfo.brightness >= 0
        label: (SysInfo.brightness >= 0 ? SysInfo.brightness : "--") + "%"
        onMoved: v => SysInfo.setBrightness(v * 100)
    }

    Row {
        width: parent.width
        spacing: 8

        FillSlider {
            width: parent.width - outputButton.width - parent.spacing
            glyph: Audio.muted || Audio.level === 0 ? "volume_off"
                : Audio.level < 0.5 ? "volume_down" : "volume_up"
            glyphIsButton: true
            accessibleName: "Volume"
            value: Audio.muted ? 0 : Audio.level
            ready: Audio.ready
            label: Math.round((Audio.muted ? 0 : Audio.level) * 100) + "%"
            onMoved: v => {
                if (Audio.muted)
                    Audio.toggleMuted();
                Audio.setVolume(v);
            }
            onGlyphClicked: Audio.toggleMuted()
        }

        Rectangle {
            id: outputButton

            width: Theme.chipHeight
            height: Theme.chipHeight
            radius: Theme.chipRadius
            color: outputMouse.containsMouse || activeFocus ? Theme.chipHover : Theme.chip
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: "Choose audio output"
            Accessible.description: Audio.outputName
            Accessible.onPressAction: Popouts.openPanel("audio", "right")
            border.width: activeFocus ? 1 : 0
            border.color: Theme.accent

            Behavior on color {
                ColorAnimation { duration: Theme.chipFadeDuration }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                        || event.key === Qt.Key_Space) {
                    Popouts.openPanel("audio", "right");
                    event.accepted = true;
                }
            }

            Sym {
                anchors.centerIn: parent
                name: "chevron_right"
                size: Theme.iconSmall
                color: Theme.icon
            }

            MouseArea {
                id: outputMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Popouts.openPanel("audio", "right")
            }
        }
    }

    // ---- Capture actions -------------------------------------------------
    Row {
        width: parent.width
        spacing: Theme.panelRowSpacing

        Repeater {
            model: [
                { glyph: "photo_camera", label: "Screenshot", cmd: root.binDir + "screenshot region" },
                { glyph: "", label: "", cmd: "" },
                { glyph: "document_scanner", label: "OCR", cmd: root.binDir + "screen-ocr" }
            ]

            delegate: Rectangle {
                id: action

                required property var modelData
                required property int index
                // The middle slot is the recorder, which reflects its
                // singleton's state rather than firing a script blindly.
                readonly property bool isRecord: index === 1
                readonly property bool recording: isRecord && Recorder.active

                width: (root.width - 2 * root.padding
                    - 2 * Theme.panelRowSpacing) / 3
                height: Theme.chipHeight
                radius: Theme.chipRadius
                color: recording ? Theme.redBg
                    : actionMouse.containsMouse ? Theme.chipHover : Theme.chip

                Behavior on color {
                    ColorAnimation { duration: Theme.chipFadeDuration }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 7

                    Sym {
                        anchors.verticalCenter: parent.verticalCenter
                        name: action.isRecord
                            ? (action.recording ? "stop_circle" : "radio_button_checked")
                            : action.modelData.glyph
                        size: Theme.iconSmall
                        color: action.recording ? Theme.redText
                            : action.isRecord ? Theme.red
                            : actionMouse.containsMouse ? Theme.textHi : Theme.textMid
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: action.isRecord
                            ? (action.recording ? "Stop" : "Record")
                            : action.modelData.label
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontMicro
                        font.weight: Theme.weightMedium
                        color: action.recording ? Theme.redText
                            : actionMouse.containsMouse ? Theme.textHi : Theme.textMid
                    }
                }

                MouseArea {
                    id: actionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (action.isRecord) {
                            Recorder.toggle();
                            Popouts.close();
                        } else {
                            root.run(action.modelData.cmd);
                        }
                    }
                }
            }
        }
    }

    // ---- System stats ----------------------------------------------------
    Grid {
        columns: 3
        columnSpacing: Theme.panelSectionSpacing
        rowSpacing: Theme.panelSectionSpacing
        width: parent.width

        StatCard {
            label: "CPU"
            display: Math.round(SysInfo.cpuUsage) + "%"
            fraction: SysInfo.cpuUsage / 100
        }

        StatCard {
            label: "RAM"
            display: Math.round(SysInfo.memUsage) + "%"
            fraction: SysInfo.memUsage / 100
        }

        StatCard {
            label: "TEMP"
            display: SysInfo.cpuTemp + "°"
            fraction: SysInfo.cpuTemp / 100
            tone: SysInfo.cpuTemp >= 80 ? Theme.redText : SysInfo.cpuTemp >= 65 ? Theme.amber : Theme.textHi
            barTone: SysInfo.cpuTemp >= 80 ? Theme.red : SysInfo.cpuTemp >= 65 ? Theme.amber : Theme.accent
        }
    }

    // ---- Footer ----------------------------------------------------------
    Row {
        width: parent.width
        spacing: Theme.panelRowSpacing

        Rectangle {
            width: settingsLabel.x + settingsLabel.implicitWidth + 9
            height: Theme.chipHeight
            radius: Theme.chipRadius
            color: settingsMouse.containsMouse ? Theme.chip : "transparent"

            Behavior on color {
                ColorAnimation { duration: Theme.chipFadeDuration }
            }

            Sym {
                id: settingsMark
                x: 7
                anchors.verticalCenter: parent.verticalCenter
                name: "settings"
                size: Theme.iconSmall
                symWeight: 450
                color: settingsMouse.containsMouse ? Theme.textHi : Theme.icon
            }

            Text {
                id: settingsLabel
                anchors.left: settingsMark.right
                anchors.leftMargin: 7
                anchors.verticalCenter: parent.verticalCenter
                text: "Settings"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontMicro
                font.weight: Theme.weightMedium
                color: settingsMouse.containsMouse ? Theme.textHi : Theme.textLow
            }

            MouseArea {
                id: settingsMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Settings.showPanel()
            }
        }

        Rectangle {
            width: Theme.chipHeight
            height: Theme.chipHeight
            radius: Theme.chipRadius
            color: keysMouse.containsMouse ? Theme.chip : "transparent"

            Behavior on color {
                ColorAnimation { duration: Theme.chipFadeDuration }
            }

            Sym {
                anchors.centerIn: parent
                name: "keyboard"
                size: Theme.iconSmall
                color: keysMouse.containsMouse ? Theme.textHi : Theme.icon
            }

            MouseArea {
                id: keysMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Session.openKeys()
            }
        }
    }
}
