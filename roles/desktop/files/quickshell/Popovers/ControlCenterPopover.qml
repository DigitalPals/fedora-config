pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import "../Common"

// Control Center v2 (design 1f): DMS-style density — compact toggle
// grid, blocked volume/brightness meters, CPU/RAM/temp stats, capture
// actions, and a quiet session footer.
Surface {
    id: root

    implicitWidth: Theme.popWideWidth
    padding: Theme.surfacePadding
    spacing: 8

    readonly property var wifiDevice: Networking.devices.values.find(d => d.networks !== undefined) ?? null
    readonly property var wifiActive: wifiDevice ? (wifiDevice.networks.values.find(n => n.connected) ?? null) : null
    readonly property var btAdapter: Bluetooth.defaultAdapter

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property int volume: sink && sink.audio ? Math.round(sink.audio.volume * 100) : 0

    readonly property string lockCmd: "hyprlock --config " + Quickshell.env("HOME") + "/.config/hypr/hyprlock.conf --immediate-render --no-fade-in"
    readonly property string binDir: Quickshell.env("HOME") + "/.local/bin/"

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    function run(cmd) {
        Quickshell.execDetached(["sh", "-c", cmd]);
        Popouts.close();
    }

    // Compact quick-toggle tile: stacked icon + label, brand-lit when on.
    component Tile: Rectangle {
        id: tile

        property string glyph: ""
        property string iconSource: ""
        property string title
        property bool on: false
        property bool chevron: false
        signal toggled
        signal expanded

        width: (root.width - 2 * root.padding - 12) / 3
        height: Theme.tileHeight
        radius: Theme.rowRadius
        color: tile.on ? (tileMouse.containsMouse ? Theme.accentBg : Theme.accentBgSoft)
             : (tileMouse.containsMouse ? Theme.hoverFill : Theme.cardFill)

        Column {
            anchors.centerIn: parent
            spacing: 4

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 16
                height: 16

                Text {
                    visible: tile.glyph !== ""
                    anchors.centerIn: parent
                    text: tile.glyph
                    font.family: Theme.fontIcon
                    font.pixelSize: Theme.fontBody
                    color: tile.on ? Theme.accent : Theme.textFaint
                }

                Image {
                    visible: tile.iconSource !== ""
                    anchors.centerIn: parent
                    width: 13
                    height: 13
                    sourceSize: Qt.size(26, 26)
                    source: tile.iconSource
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.title
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                font.weight: Theme.weightMedium
                color: tile.on ? Theme.textHi : Theme.textLow
            }
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton && tile.chevron)
                    tile.expanded();
                else
                    tile.toggled();
            }
        }

        // Corner chevron: morphs the surface to the detail view in place.
        Rectangle {
            visible: tile.chevron
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 3
            anchors.rightMargin: 3
            width: 16
            height: 16
            radius: 5
            color: chevMouse.containsMouse ? Theme.hoverFillStrong : "transparent"

            Text {
                anchors.centerIn: parent
                text: ""
                font.family: Theme.fontIcon
                font.pixelSize: Theme.fontCaption
                color: chevMouse.containsMouse ? Theme.textHi : tile.on ? Theme.textLow : Theme.textFaint
            }

            MouseArea {
                id: chevMouse
                anchors.fill: parent
                anchors.margins: -3
                hoverEnabled: true
                onClicked: tile.expanded()
            }
        }
    }

    // Small labelled meter row for the sliders card.
    component MeterRow: Column {
        id: meterRow

        property string glyph
        property string label
        property int percent: 0
        property bool ready: true
        signal moved(real value)

        width: parent.width
        spacing: 6
        opacity: ready ? 1 : 0.4

        Item {
            width: parent.width
            height: Math.max(meterGlyph.implicitHeight, meterLabel.implicitHeight,
                meterValue.implicitHeight)

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    id: meterGlyph
                    anchors.verticalCenter: parent.verticalCenter
                    text: meterRow.glyph
                    font.family: Theme.fontIcon
                    font.pixelSize: Theme.fontBody
                    color: Theme.textLow
                }

                Text {
                    id: meterLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: meterRow.label
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    font.weight: Theme.weightSemibold
                    font.letterSpacing: 0.6
                    color: Theme.textDim
                }
            }

            Text {
                id: meterValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: meterRow.percent >= 0 ? meterRow.percent + "%" : "--"
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSecondary
                font.weight: Theme.weightSemibold
                color: Theme.textMid
            }
        }

        BlockMeter {
            width: parent.width
            height: 10
            interactive: meterRow.ready
            value: Math.max(0, meterRow.percent) / 100
            onMoved: v => meterRow.moved(v)
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
        radius: 10
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

    // ---- Quick toggles -------------------------------------------------
    Grid {
        columns: 3
        columnSpacing: 6
        rowSpacing: 6
        width: parent.width

        Tile {
            glyph: ""
            title: "Wi-Fi"
            on: Networking.wifiEnabled
            chevron: true
            onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
            onExpanded: Popouts.openPanel("wifi", "right")
        }

        Tile {
            glyph: ""
            title: "Bluetooth"
            on: root.btAdapter !== null && root.btAdapter.enabled
            chevron: true
            onToggled: {
                if (root.btAdapter)
                    root.btAdapter.enabled = !root.btAdapter.enabled;
            }
            onExpanded: Popouts.openPanel("bluetooth", "right")
        }

        Tile {
            iconSource: Quickshell.shellDir + "/assets/tailscale" + (SysInfo.tsRunning ? "" : "-dim") + ".svg"
            title: "Tailscale"
            on: SysInfo.tsRunning
            chevron: true
            onToggled: {
                Quickshell.execDetached(["sh", "-c", SysInfo.tsRunning ? "tailscale down" : "tailscale up"]);
                tsRefresh.restart();
            }
            onExpanded: Popouts.openPanel("tailscale", "right")
        }

        Tile {
            glyph: ""
            title: "Idle inhibit"
            on: SysInfo.idleInhibited
            onToggled: SysInfo.idleInhibited = !SysInfo.idleInhibited
        }

        Tile {
            glyph: ""
            title: "Do not disturb"
            on: Notifs.dnd
            onToggled: Notifs.setDnd(!Notifs.dnd)
        }

        Tile {
            glyph: ""
            title: "Night light"
            on: SysInfo.nightLight
            onToggled: SysInfo.nightLight = !SysInfo.nightLight
        }
    }

    Timer {
        id: tsRefresh
        interval: 1200
        onTriggered: SysInfo.refreshTailscale()
    }

    // ---- Volume / brightness meters -------------------------------------
    Rectangle {
        width: parent.width
        height: metersCol.implicitHeight + 24
        radius: 10
        color: Theme.cardFill

        Column {
            id: metersCol
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 11

            MeterRow {
                glyph: ""
                label: "VOLUME"
                percent: root.sink && root.sink.audio ? root.volume : -1
                ready: root.sink !== null && root.sink.audio !== null
                onMoved: v => {
                    if (root.sink && root.sink.audio)
                        root.sink.audio.volume = v;
                }
            }

            MeterRow {
                glyph: ""
                label: "BRIGHTNESS"
                percent: SysInfo.brightness
                ready: SysInfo.brightness >= 0
                onMoved: v => SysInfo.setBrightness(v * 100)
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

    // ---- Capture actions ---------------------------------------------------
    Grid {
        columns: 3
        columnSpacing: 6
        rowSpacing: 6
        width: parent.width

        Repeater {
            model: [
                { glyph: "", tone: Theme.icon, label: "Screenshot", cmd: root.binDir + "screenshot region" },
                { glyph: "", tone: Theme.red, label: "Record", cmd: root.binDir + "screen-record" },
                { glyph: "", tone: Theme.icon, label: "OCR", cmd: root.binDir + "screen-ocr" }
            ]

            delegate: Rectangle {
                id: action

                required property var modelData

                width: (root.width - 2 * root.padding - 12) / 3
                height: Theme.controlHeight
                radius: 8
                color: actionMouse.containsMouse ? Theme.hoverFillStrong : Theme.hoverFill

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: action.modelData.glyph
                        font.family: Theme.fontIcon
                        font.pixelSize: Theme.fontBody
                        color: action.modelData.tone
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: action.modelData.label
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontSecondary
                        font.weight: Theme.weightMedium
                        color: Theme.textMid
                    }
                }

                MouseArea {
                    id: actionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.run(action.modelData.cmd)
                }
            }
        }
    }

    HDivider {}

    // ---- Session footer ------------------------------------------------------
    Item {
        width: parent.width
        height: Theme.controlHeight

        Text {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            text: SysInfo.user + " @ " + SysInfo.host
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: Theme.textLow
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            // Shell settings gear (design v2) — opens the settings window,
            // which closes this popout on its way in.
            Rectangle {
                width: 26
                height: Theme.controlHeight
                radius: 6
                color: gearMouse.containsMouse ? Theme.hoverFillStrong : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "" // gear
                    font.family: Theme.fontIcon
                    font.pixelSize: Theme.fontBody
                    color: gearMouse.containsMouse ? Theme.textHi : Theme.textLow
                }

                MouseArea {
                    id: gearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Settings.showPanel()
                }
            }

            Repeater {
                model: [
                    { glyph: "", tip: "Lock", danger: false, cmd: root.lockCmd },
                    { glyph: "", tip: "Suspend", danger: false, cmd: "systemctl suspend" },
                    { glyph: "", tip: "Reboot", danger: false, cmd: "systemctl reboot" },
                    { glyph: "", tip: "Shut down", danger: true, cmd: "systemctl poweroff" }
                ]

                delegate: Rectangle {
                    id: sess

                    required property var modelData

                    width: 26
                    height: Theme.controlHeight
                    radius: 6
                    color: sessMouse.containsMouse
                        ? (sess.modelData.danger ? Theme.redBg : Theme.hoverFillStrong)
                        : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: sess.modelData.glyph
                        font.family: Theme.fontIcon
                        font.pixelSize: Theme.fontBody
                        color: sess.modelData.danger ? Theme.redText : sessMouse.containsMouse ? Theme.textHi : Theme.textLow
                    }

                    MouseArea {
                        id: sessMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.run(sess.modelData.cmd)
                    }
                }
            }
        }
    }
}
