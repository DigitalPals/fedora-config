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
        }
        onReleased: {
            SysInfo.release();
            Tailscale.release();
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

        width: (root.width - 2 * root.padding - 10) / 2
        height: Theme.tileHeight
        radius: Theme.cardRadius
        color: tile.on ? Theme.accentSoft : Theme.tile
        scale: tileMouse.pressed ? 0.97 : 1

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

        Rectangle {
            x: 11
            anchors.verticalCenter: parent.verticalCenter
            width: 38
            height: 38
            radius: 19
            color: tile.on ? Theme.accent : Theme.chipHover

            Behavior on color {
                ColorAnimation { duration: Theme.surfaceDuration }
            }

            Sym {
                anchors.centerIn: parent
                name: tile.glyph
                size: 19
                fill: tile.on ? 1 : 0
                color: tile.on ? Theme.textOnAccent : Theme.textMid
            }
        }

        Column {
            x: 60
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - 32
            spacing: 1

            Text {
                width: parent.width
                text: tile.title
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontSecondary
                font.weight: Theme.weightBold
                color: Theme.textHi
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: tile.sub
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontTiny
                font.weight: Theme.weightSemibold
                color: Theme.textMid
                elide: Text.ElideRight
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            radius: 12
            color: chevMouse.containsMouse ? Theme.chipHover : "transparent"

            Sym {
                anchors.centerIn: parent
                name: "chevron_right"
                size: Theme.fontBody
                symWeight: 600
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

    // Round quick toggle: a 46px circle that lights on the accent, with its
    // label underneath. Right-click opens the detail view where one exists.
    component RoundToggle: Item {
        id: toggle

        property string glyph: ""
        property string iconSource: ""
        property string title
        property bool on: false
        property bool detail: false
        signal toggled
        signal expanded

        width: (root.width - 2 * root.padding - 4 * 8) / 5
        height: circle.height + 7 + toggleLabel.implicitHeight + 8

        Rectangle {
            anchors.fill: parent
            radius: Theme.rowRadius
            color: toggleMouse.containsMouse ? Theme.chip : "transparent"

            Behavior on color {
                ColorAnimation { duration: Theme.chipFadeDuration }
            }
        }

        Rectangle {
            id: circle
            anchors.horizontalCenter: parent.horizontalCenter
            y: 4
            width: 46
            height: 46
            radius: 23
            color: toggle.on ? Theme.accent : Theme.tile
            scale: toggleMouse.pressed ? 0.92 : 1

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
                size: Theme.iconLarge
                fill: toggle.on ? 1 : 0
                color: toggle.on ? Theme.textOnAccent : Theme.textMid
            }

            Image {
                visible: toggle.iconSource !== ""
                anchors.centerIn: parent
                width: 20
                height: 20
                sourceSize: Qt.size(40, 40)
                source: toggle.iconSource
            }
        }

        Text {
            id: toggleLabel
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: circle.bottom
            anchors.topMargin: 7
            text: toggle.title
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontMicro
            font.weight: Theme.weightBold
            font.letterSpacing: 0.2
            color: Theme.textLow
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

        width: (root.width - 2 * root.padding - 12) / 3
        height: statCol.implicitHeight + 18
        radius: Theme.rowRadius
        color: Theme.cardFill

        Column {
            id: statCol
            x: 11
            y: 9
            width: parent.width - 22
            spacing: 5

            Text {
                text: stat.label
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                font.weight: Theme.weightSemibold
                font.letterSpacing: 0.6
                color: Theme.textDim
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

    // ---- Radio tiles -----------------------------------------------------
    Row {
        width: parent.width
        spacing: 10

        BigTile {
            glyph: "wifi"
            title: "Internet"
            sub: !WifiState.enabled ? "Off" : WifiState.connected ? WifiState.name : "On"
            on: WifiState.enabled
            onToggled: WifiState.setEnabled(!WifiState.enabled)
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
            onToggled: BluetoothState.toggle()
            onExpanded: Popouts.openPanel("bluetooth", "right")
        }
    }

    // ---- Quick toggles ---------------------------------------------------
    Row {
        width: parent.width
        spacing: 8

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
            onToggled: SysInfo.nightLight = !SysInfo.nightLight
        }

        RoundToggle {
            glyph: "coffee"
            title: "Idle inhibit"
            on: SysInfo.idleInhibited
            onToggled: SysInfo.idleInhibited = !SysInfo.idleInhibited
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
    Rectangle {
        visible: PowerProfiles.hasPerformanceProfile
        width: parent.width
        height: Theme.controlHeight
        radius: height / 2
        color: Theme.tile

        Behavior on color {
            ColorAnimation { duration: Theme.surfaceDuration }
        }

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
                    radius: height / 2
                    color: current ? Theme.accent
                        : modeMouse.containsMouse ? Theme.chipHover : "transparent"

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
                            color: mode.current ? Theme.textOnAccent : Theme.textFaint
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: mode.modelData.label
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontMicro
                            font.weight: Theme.weightHeavy
                            font.letterSpacing: 0.2
                            color: mode.current ? Theme.textOnAccent : Theme.textFaint
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

    FillSlider {
        width: parent.width
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

    // ---- Capture actions -------------------------------------------------
    Row {
        width: parent.width
        spacing: 8

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

                width: (root.width - 2 * root.padding - 16) / 3
                height: 38
                radius: 19
                color: recording ? Theme.redBg
                    : actionMouse.containsMouse ? Theme.chipHover : Theme.tile

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
                        size: Theme.iconSmall + 2
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
                        font.pixelSize: Theme.fontTiny
                        font.weight: Theme.weightHeavy
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
        columnSpacing: 6
        rowSpacing: 6
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
        spacing: 6

        Rectangle {
            width: parent.width - 36 - parent.spacing
            height: 36
            radius: 14
            color: settingsMouse.containsMouse ? Theme.chip : "transparent"

            Behavior on color {
                ColorAnimation { duration: Theme.chipFadeDuration }
            }

            Rectangle {
                x: 5
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 26
                radius: 13
                color: Theme.chip

                Sym {
                    anchors.centerIn: parent
                    name: "settings" // gear
                    size: Theme.fontBody
                    symWeight: 600
                    color: settingsMouse.containsMouse ? Theme.textHi : Theme.textLow
                }
            }

            Text {
                x: 40
                anchors.verticalCenter: parent.verticalCenter
                text: "Shell settings"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontTiny
                font.weight: Theme.weightBold
                color: settingsMouse.containsMouse ? Theme.textHi : Theme.textLow
            }

            Sym {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                name: "chevron_right"
                size: Theme.fontBody
                symWeight: 600
                color: Theme.textFaint
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
            width: 36
            height: 36
            radius: 14
            color: keysMouse.containsMouse ? Theme.chip : "transparent"

            Behavior on color {
                ColorAnimation { duration: Theme.chipFadeDuration }
            }

            Sym {
                anchors.centerIn: parent
                name: "keyboard"
                size: Theme.iconMedium
                color: keysMouse.containsMouse ? Theme.textHi : Theme.textLow
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
