import QtQuick
import Quickshell
import "../Common"

// System page (design v2): clock/temperature formats, night-light warmth,
// OSD placement, T3 usage polling, and the config-file footer.
Item {
    id: page

    // One 1s tick drives both the live clock caption and the poll
    // countdown, derived from Usage state without mutating it.
    property double nowSecs: Date.now() / 1000

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: page.nowSecs = Date.now() / 1000
    }

    readonly property date nowDate: new Date(page.nowSecs * 1000)
    readonly property int pollLeft: Usage.updatedAt > 0
        ? Math.max(0, Usage.pollIntervalSecs - Math.floor(page.nowSecs - Usage.updatedAt / 1000))
        : Usage.nextPollSecs

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 10

        SectionHeader {
            label: "FORMATS"
        }

        PickerRow {
            width: parent.width
            label: "Clock"
            model: [{ value: true, label: "24 h" }, { value: false, label: "12 h" }]
            current: Settings.clock24
            caption: Qt.formatDateTime(page.nowDate, Settings.clock24 ? "HH:mm" : "h:mm AP")
            dirty: Settings.clock24 !== Settings.defaults.clock24
            onPicked: value => Settings.set("clock24", value)
            onResetRequested: Settings.resetKeys(["clock24"])
        }

        PickerRow {
            width: parent.width
            label: "Temperature"
            model: [{ value: "c", label: "°C" }, { value: "f", label: "°F" }]
            current: Settings.unit
            caption: Weather.ready ? Weather.temp + "° outside" : ""
            dirty: Settings.unit !== Settings.defaults.unit
            onPicked: value => Settings.set("unit", value)
            onResetRequested: Settings.resetKeys(["unit"])
        }

        SectionHeader {
            label: "NIGHT LIGHT"
        }

        SliderRow {
            width: parent.width
            label: "Warmth"
            min: 1900
            max: 4500
            step: 50
            value: Settings.warmth
            unit: "K"
            gradientTrack: true
            dirty: Settings.warmth !== Settings.defaults.warmth
            onMoved: value => Settings.set("warmth", value)
            onResetRequested: Settings.resetKeys(["warmth"])
        }

        Text {
            leftPadding: 100
            text: "Tint applies while Night light is on in Control Center — "
                + (SysInfo.nightLight ? "currently on" : "currently off")
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: Theme.textDim
        }

        SectionHeader {
            label: "OSD"
        }

        PickerRow {
            width: parent.width
            label: "Placement"
            model: [{ value: "top", label: "Top center" }, { value: "bottom", label: "Bottom center" }]
            current: Settings.osd
            caption: "volume / brightness popup"
            captionMono: false
            dirty: Settings.osd !== Settings.defaults.osd
            onPicked: value => Settings.set("osd", value)
            onResetRequested: Settings.resetKeys(["osd"])
        }

        SectionHeader {
            label: "T3 USAGE"
        }

        PickerRow {
            width: parent.width
            label: "Poll every"
            model: [{ value: 60, label: "1 min" }, { value: 300, label: "5 min" }, { value: 600, label: "10 min" }]
            current: Settings.pollMax
            caption: "next " + Math.floor(page.pollLeft / 60) + ":"
                + String(page.pollLeft % 60).padStart(2, "0")
            dirty: Settings.pollMax !== Settings.defaults.pollMax
            onPicked: value => Settings.set("pollMax", value)
            onResetRequested: Settings.resetKeys(["pollMax"])
        }
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 8

        SectionHeader {
            label: "CONFIG"
        }

        Item {
            width: parent.width
            height: 16

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "~/.local/state/quickshell/shell-settings.json"
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontCaption
                color: Theme.textFaint
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Text {
                    text: "Open"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    font.weight: Theme.weightMedium
                    color: Theme.accent

                    MouseArea {
                        anchors.fill: parent
                        onClicked: Quickshell.execDetached(["xdg-open", Settings.filePath])
                    }
                }

                Text {
                    text: "Reset all"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    font.weight: Theme.weightMedium
                    color: Theme.redText

                    MouseArea {
                        anchors.fill: parent
                        onClicked: Settings.resetAll()
                    }
                }
            }
        }
    }
}
