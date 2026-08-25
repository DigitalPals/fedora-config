pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../Common"
import "../Common/Format.js" as Format

// Control Center: the battery header, one segmented power-profile track, the
// two radio rows, one grid of quick actions, the filled sliders, the system
// stats and the shell-settings footer.
//
// The redesign is about geometry, not new controls. This panel used to stack
// six different shapes — 34px radio rows, five square toggles with labels
// under them, a 16px-tall profile pill inside a 26px box, a 34px slider beside
// a 26px chevron, 26px action chips, and three floating stat stacks — on one
// flat 12px rhythm with no section marks anywhere. There are three shapes now
// — a full-width row, a grid tile, a segmented track — separated by the
// SectionLabel the rest of the shell already draws.
//
// The battery is the other half of it. This is the panel the status pill
// opens, and the pill's most-read glyph is the battery, which had no
// representation here at all; the charge and the profile it drives now open
// the panel, and BatteryPopover stays the drill-in.
Surface {
    id: root

    implicitWidth: Theme.popWidth
    padding: Theme.surfacePadding
    spacing: Theme.panelSectionSpacing

    readonly property string binDir: Quickshell.env("HOME") + "/.local/bin/"
    readonly property var btConnected: BluetoothState.devices.filter(d => d.connected)

    readonly property real contentWidth: Math.max(0, root.width - 2 * root.padding)
    // Eight quick actions in one 4x2 grid. At this cell width every label
    // fits on one line; the old five-wide row gave each 73px, which elided
    // "Idle inhibit" and left the three capture chips as a second, narrower
    // geometry underneath.
    readonly property int tileSpacing: 8
    readonly property real tileWidth:
        Math.max(0, (contentWidth - 3 * tileSpacing) / 4)
    readonly property int tileHeight: 58
    // Between the 34px list row and the 48px panel tile: the icon lane plus
    // two lines of copy, which is what moves the status off the right edge.
    // A long SSID gets ~300px here against ~240px when it shared the row.
    readonly property int radioRowHeight: 44
    readonly property int statHeight: 34

    // Battery tone. Charging and full are never a warning, however low the
    // reading is, so every threshold below is gated on discharging.
    readonly property bool onBattery:
        Battery.isLaptop && !Battery.charging && !Battery.full
    readonly property bool battCritical: onBattery && Battery.percent <= 10
    readonly property bool battLow: onBattery && Battery.percent <= 20
    readonly property bool battWarn: battCritical || battLow
    readonly property color battTone: battCritical ? Theme.redText
        : battLow ? Theme.amber : Theme.textHi
    readonly property color battFill: battCritical ? Theme.red
        : battLow ? Theme.amber : Theme.accent

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

    function fmtDuration(secs) {
        if (!secs || secs <= 0)
            return "";
        const h = Math.floor(secs / Format.HOUR);
        const m = Math.round((secs % Format.HOUR) / Format.MINUTE);
        return h > 0 ? `${h} h ${Format.pad2(m)} min` : `${m} min`;
    }

    // Radio row: mark, name, live status underneath, and the chevron into the
    // detail panel. Two lines because the status used to compete with the
    // title for right-aligned space in a 34px row.
    //
    // One activation, not two. The row used to separate left-click from
    // right-click and from a chevron hit area, and all three called
    // openPanel() with the same arguments — three targets for one outcome.
    component RadioRow: Rectangle {
        id: radio

        property string glyph: ""
        property string title
        property string sub
        property bool on: false
        signal activated

        width: parent ? parent.width : 0
        height: root.radioRowHeight
        radius: Theme.chipRadius
        color: radioMouse.containsMouse ? Theme.chip : "transparent"
        scale: radioMouse.pressed ? 0.99 : 1

        Accessible.role: Accessible.Button
        Accessible.name: radio.title
        Accessible.description: radio.sub
        Accessible.onPressAction: radio.activated()

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

        Item {
            id: radioMark
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28

            Sym {
                anchors.centerIn: parent
                name: radio.glyph
                size: Theme.iconLarge
                fill: radio.on ? 1 : 0
                color: radio.on ? Theme.accent : Theme.icon
            }
        }

        Column {
            anchors.left: radioMark.right
            anchors.leftMargin: 10
            anchors.right: radioChevron.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                text: radio.title
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontSecondary
                font.weight: Theme.weightMedium
                color: Theme.textHi
            }

            Text {
                width: parent.width
                text: radio.sub
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontMicro
                color: Theme.textDim
                elide: Text.ElideRight
            }
        }

        Item {
            id: radioChevron
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28

            Sym {
                anchors.centerIn: parent
                name: "chevron_right"
                size: Theme.iconMedium
                symWeight: 450
                color: radioMouse.containsMouse ? Theme.textHi : Theme.textFaint
            }
        }

        MouseArea {
            id: radioMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: radio.activated()
        }
    }

    // One quick action: its mark over its label, in a grid cell. A toggle
    // lights on the accent container and a one-shot action never does, which
    // is the whole rule for reading this grid.
    component QuickTile: Rectangle {
        id: tile

        property string glyph: ""
        property string iconSource: ""
        property string title
        property bool on: false
        // A running capture, which owns the red field rather than the accent.
        property bool alert: false
        property bool detail: false
        // Defaults to the shell's icon tint; the recorder overrides it so its
        // dot stays red at rest.
        property color restMark: tileMouse.containsMouse ? Theme.textHi : Theme.icon
        readonly property color mark: tile.alert ? Theme.redText
            : tile.on ? Theme.accentContainerFg : tile.restMark
        readonly property color copy: tile.alert ? Theme.redText
            : tile.on ? Theme.accentContainerFg
            : tileMouse.containsMouse ? Theme.textMid : Theme.textFaint
        signal toggled
        signal expanded

        width: root.tileWidth
        height: root.tileHeight
        radius: Theme.chipRadius
        color: tile.alert ? Theme.redBg
            : tile.on ? Theme.accentContainer
            : tileMouse.containsMouse ? Theme.chipHover : Theme.chip
        scale: tileMouse.pressed ? 0.95 : 1

        Accessible.role: Accessible.Button
        Accessible.name: tile.title
        Accessible.onPressAction: tile.toggled()

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

        Column {
            anchors.centerIn: parent
            spacing: 7

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.iconLarge
                height: Theme.iconLarge

                Sym {
                    visible: tile.glyph !== ""
                    anchors.centerIn: parent
                    name: tile.glyph
                    size: Theme.iconLarge
                    fill: tile.on || tile.alert ? 1 : 0
                    color: tile.mark
                }

                Image {
                    visible: tile.iconSource !== ""
                    anchors.centerIn: parent
                    width: Theme.iconLarge
                    height: Theme.iconLarge
                    sourceSize: Qt.size(40, 40)
                    source: tile.iconSource
                }
            }

            Text {
                // 3px either side, not more: "Idle inhibit" is the longest
                // label and needs 80 of the cell's 88.
                width: Math.max(0, tile.width - 6)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: tile.title
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontMicro
                font.weight: Theme.weightMedium
                color: tile.copy
            }
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton && tile.detail)
                    tile.expanded();
                else
                    tile.toggled();
            }
        }
    }

    // One column of the CPU / RAM / TEMP strip: the reading on the label's own
    // line rather than under it, which halves the height and lets the three
    // columns share hairlines instead of floating in 16px gutters.
    component StatColumn: Item {
        id: stat

        property string label
        property string display
        property real fraction: 0
        property color tone: Theme.textHi
        property color barTone: Theme.accent
        property real padLeft: 0
        property real padRight: 0

        height: root.statHeight

        Text {
            id: statLabel
            x: stat.padLeft
            text: stat.label
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontMicro
            font.weight: Theme.weightSemibold
            font.letterSpacing: 1
            color: Theme.textFaint
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: stat.padRight
            anchors.baseline: statLabel.baseline
            text: stat.display
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSecondary
            font.weight: Theme.weightSemibold
            font.features: Theme.tabularNumberFeatures
            color: stat.tone
        }

        BlockMeter {
            x: stat.padLeft
            width: Math.max(0, stat.width - stat.padLeft - stat.padRight)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            height: 6
            blockWidth: 3
            gap: 2
            value: stat.fraction
            fillColor: stat.barTone
        }
    }

    // ---- Battery and power profile ---------------------------------------
    Column {
        width: parent.width
        spacing: 12
        visible: Battery.isLaptop || PowerProfiles.hasPerformanceProfile

        Item {
            visible: Battery.isLaptop
            width: parent.width
            // The reading's own text box is ~37 at this size, so 40 left it
            // 1.5px of air either side and the panel's top padding did all the
            // work. This is the one row whose type is big enough to need room.
            height: 46

            // Not a Row. A Row takes its height from the children it lays out,
            // and the reading was baseline-anchored to the small "%" beside
            // it, which gives the big text a negative y: the Row measured the
            // 14px unit, the 28px numerals overhung it by an ascender, and the
            // reading sat hard against the panel's top padding no matter what
            // the group was anchored to. Sizing to the numerals and hanging
            // the unit off *their* baseline puts the ink back inside the box.
            Item {
                id: battValue
                x: 2
                anchors.verticalCenter: parent.verticalCenter
                width: battNumber.implicitWidth + 1 + battUnit.implicitWidth
                height: battNumber.implicitHeight

                Text {
                    id: battNumber
                    anchors.left: parent.left
                    anchors.top: parent.top
                    text: Math.round(Battery.percent)
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontDisplay
                    font.weight: Theme.weightSemibold
                    font.features: Theme.tabularNumberFeatures
                    color: root.battTone
                }

                Text {
                    id: battUnit
                    anchors.left: battNumber.right
                    anchors.leftMargin: 1
                    anchors.baseline: battNumber.baseline
                    text: "%"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontBody
                    font.weight: Theme.weightMedium
                    color: root.battWarn ? root.battTone : Theme.textLow
                }
            }

            Column {
                anchors.left: battValue.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Row {
                    anchors.right: parent.right
                    spacing: 5

                    Sym {
                        visible: Battery.charging
                        anchors.verticalCenter: parent.verticalCenter
                        name: "bolt"
                        size: Theme.fontSecondary
                        fill: 1
                        color: Theme.accent
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Battery.full ? "Fully charged"
                            : Battery.charging ? "Charging" : "On battery"
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontTiny
                        font.weight: Theme.weightMedium
                        color: root.battWarn ? root.battTone : Theme.textMid
                    }
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    visible: text !== ""
                    text: {
                        if (!Battery.device)
                            return "";
                        if (Battery.charging && Battery.device.timeToFull > 0)
                            return root.fmtDuration(Battery.device.timeToFull) + " until full";
                        if (!Battery.charging && !Battery.full && Battery.device.timeToEmpty > 0)
                            return root.fmtDuration(Battery.device.timeToEmpty) + " remaining";
                        return "";
                    }
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontMicro
                    color: Theme.textDim
                }
            }
        }

        BlockMeter {
            visible: Battery.isLaptop
            width: parent.width
            height: 8
            blockWidth: 4
            gap: 2
            value: Battery.percent / 100
            fillColor: root.battFill
        }

        // Only where there is a profile daemon to talk to: on a machine
        // without power-profiles-daemon this row would be three buttons that
        // do nothing. The track is the fix — the segments used to sit in a
        // 26px Item behind a 5px inset, which left them 16px tall with 15px
        // marks overflowing them and nothing to say they were one control.
        Rectangle {
            visible: PowerProfiles.hasPerformanceProfile
            width: parent.width
            height: Theme.listRowHeight
            radius: Theme.chipRadius
            color: Theme.chip

            Row {
                id: modeRow
                anchors.fill: parent
                anchors.margins: 3
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
                        radius: Theme.chipRadius - 2
                        color: mode.current ? Theme.chipHover
                            : modeMouse.containsMouse ? Theme.tile : "transparent"
                        border.width: mode.current ? 1 : 0
                        border.color: Theme.stroke

                        Accessible.role: Accessible.RadioButton
                        Accessible.name: mode.modelData.label
                        Accessible.checked: mode.current
                        Accessible.onPressAction: PowerProfiles.profile = mode.modelData.profile

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
                                font.weight: mode.current ? Theme.weightSemibold : Theme.weightMedium
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
    }

    // ---- Radios ----------------------------------------------------------
    Column {
        width: parent.width
        spacing: 0

        SectionLabel {
            text: "CONNECTIVITY"
        }

        Column {
            width: parent.width
            spacing: Theme.panelRowSpacing

            RadioRow {
                glyph: EthernetState.connected ? "lan"
                    : WifiState.enabled ? "wifi" : "wifi_off"
                title: "Internet"
                sub: EthernetState.connected && WifiState.connected ? "Ethernet + Wi-Fi"
                    : EthernetState.connected ? "Ethernet"
                    : WifiState.connected ? WifiState.name
                    : WifiState.enabled ? "No connection" : "Offline"
                on: EthernetState.connected || WifiState.connected
                onActivated: Popouts.openPanel("wifi", "right")
            }

            RadioRow {
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
                onActivated: Popouts.openPanel("bluetooth", "right")
            }
        }
    }

    // ---- Quick actions ---------------------------------------------------
    // The five toggles and the three capture chips were two ragged rows of
    // different widths and different anatomy. They are eight cells of one
    // grid now: state lights the cell, a one-shot action never does.
    Column {
        width: parent.width
        spacing: 0

        SectionLabel {
            text: "QUICK ACTIONS"
        }

        Grid {
            width: parent.width
            columns: 4
            spacing: root.tileSpacing

            QuickTile {
                glyph: "dark_mode"
                title: "Dark mode"
                on: Theme.dark
                onToggled: Settings.themeMode = Theme.dark ? "light" : "dark"
            }

            QuickTile {
                glyph: "do_not_disturb_on"
                title: "Focus"
                on: Notifs.dnd
                onToggled: Notifs.setDnd(!Notifs.dnd)
            }

            QuickTile {
                glyph: "nightlight"
                title: "Night light"
                on: SysInfo.nightLight
                onToggled: SysInfo.toggleNightLight()
            }

            QuickTile {
                glyph: "coffee"
                title: "Idle inhibit"
                on: SysInfo.idleInhibited
                onToggled: SysInfo.toggleIdleInhibited()
            }

            QuickTile {
                iconSource: Quickshell.shellDir + "/assets/tailscale" + (Tailscale.running ? "" : "-dim") + ".svg"
                title: "Tailscale"
                on: Tailscale.running
                detail: true
                onToggled: Tailscale.toggle()
                onExpanded: Popouts.openPanel("tailscale", "right")
            }

            QuickTile {
                glyph: "photo_camera"
                title: "Screenshot"
                onToggled: root.run(root.binDir + "screenshot region")
            }

            QuickTile {
                glyph: Recorder.active ? "stop_circle" : "radio_button_checked"
                title: Recorder.active ? "Stop" : "Record"
                alert: Recorder.active
                restMark: Theme.red
                onToggled: {
                    Recorder.toggle();
                    Popouts.close();
                }
            }

            QuickTile {
                glyph: "document_scanner"
                title: "OCR"
                onToggled: root.run(root.binDir + "screen-ocr")
            }
        }
    }

    // ---- Brightness / volume ---------------------------------------------
    Column {
        width: parent.width
        spacing: 0

        SectionLabel {
            text: "DISPLAY & SOUND"
        }

        Column {
            width: parent.width
            spacing: 6

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

                // Squared off against the slider it sits beside; it used to be
                // a 26px chip top-aligned against a 34px track.
                Rectangle {
                    id: outputButton

                    width: Theme.listRowHeight
                    height: Theme.listRowHeight
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
                        size: Theme.iconMedium
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
        }
    }

    // ---- System stats ----------------------------------------------------
    Column {
        width: parent.width
        spacing: 0

        SectionLabel {
            text: "SYSTEM"
        }

        Row {
            id: statsRow

            width: parent.width
            spacing: 0
            // The three meters read against one 0..100 scale, so they must be
            // the same length. Equal column widths would not do it: the middle
            // column pays a gutter on both sides and the outer two only on
            // their inner side. So the meters are equal and the middle column
            // is the wider one. Two of the width belongs to the hairlines.
            readonly property real gutter: 14
            readonly property real meterWidth:
                Math.max(0, (width - 2 - 4 * gutter) / 3)

            StatColumn {
                width: statsRow.meterWidth + statsRow.gutter
                padRight: statsRow.gutter
                label: "CPU"
                display: Math.round(SysInfo.cpuUsage) + "%"
                fraction: SysInfo.cpuUsage / 100
            }

            Rectangle {
                width: 1
                height: root.statHeight
                color: Theme.hairlineSoft
            }

            StatColumn {
                width: statsRow.meterWidth + 2 * statsRow.gutter
                padLeft: statsRow.gutter
                padRight: statsRow.gutter
                label: "RAM"
                display: Math.round(SysInfo.memUsage) + "%"
                fraction: SysInfo.memUsage / 100
            }

            Rectangle {
                width: 1
                height: root.statHeight
                color: Theme.hairlineSoft
            }

            StatColumn {
                width: statsRow.meterWidth + statsRow.gutter
                padLeft: statsRow.gutter
                label: "TEMP"
                display: SysInfo.cpuTemp + "°"
                fraction: SysInfo.cpuTemp / 100
                tone: SysInfo.cpuTemp >= 80 ? Theme.redText
                    : SysInfo.cpuTemp >= 65 ? Theme.amber : Theme.textHi
                barTone: SysInfo.cpuTemp >= 80 ? Theme.red
                    : SysInfo.cpuTemp >= 65 ? Theme.amber : Theme.accent
            }
        }
    }

    // ---- Footer ----------------------------------------------------------
    // The two actions bookend the panel instead of crowding its left corner.
    Item {
        width: parent.width
        height: Theme.chipHeight

        Rectangle {
            anchors.top: parent.top
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
            anchors.right: parent.right
            width: Theme.chipHeight
            height: Theme.chipHeight
            radius: Theme.chipRadius
            color: keysMouse.containsMouse ? Theme.chip : "transparent"

            Accessible.role: Accessible.Button
            Accessible.name: "Keyboard shortcuts"
            Accessible.onPressAction: Session.openKeys()

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
