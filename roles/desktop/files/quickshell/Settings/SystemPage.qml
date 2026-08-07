import QtQuick
import Quickshell
import "../Common"

// System page (design v2): clock/temperature formats, night-light warmth,
// OSD placement, T3 usage polling, and the config-file footer.
SettingsPage {
    id: page

    // This tick drives the live clock caption. The poll countdown used to
    // ride on it too; Usage derives that itself now, and ticks it only
    // while a view has asked for it.
    property double nowSecs: Date.now() / 1000
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: page.nowSecs = Date.now() / 1000
    }

    Claim {
        active: page.visible
        onClaimed: Usage.acquireCountdown()
        onReleased: Usage.releaseCountdown()
    }

    function openConfig() {
        Settings.saveNow();
        Qt.callLater(() => Quickshell.execDetached(["xdg-open", Settings.filePath]));
    }

    readonly property date nowDate: new Date(page.nowSecs * 1000)
    // Usage owns this now; it used to be recomputed here because the
    // shared counter only advanced while the usage popover was open.
    readonly property int pollLeft: Usage.nextPollSecs

    Column {
        id: generalSettings
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 8

        SectionHeader {
            label: "GENERAL"
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

        SliderRow {
            width: parent.width
            label: "Scroll speed"
            min: 0.2
            max: 2.0
            step: 0.1
            decimals: 1
            value: Settings.scrollFactor
            unit: "×"
            dirty: Math.abs(Settings.scrollFactor - Settings.defaults.scrollFactor) > 0.001
            onMoved: value => Settings.set("scrollFactor", value)
            onResetRequested: Settings.resetKeys(["scrollFactor"], "Touchpad scroll speed")
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
            width: parent.width
            leftPadding: page.width < 440 ? 0 : Settings.font === "mono" ? 132 : 100
            text: "Tint applies while Night light is on in Control Center — "
                + (SysInfo.nightLight ? "currently on" : "currently off")
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: Theme.textDim
            wrapMode: Text.Wrap
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
        y: generalSettings.height + 10
        width: parent.width
        spacing: 8

        SectionHeader {
            label: "CONFIG"
        }

        SettingsCard {
            width: parent.width
            implicitHeight: 52

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(80, parent.width - configActions.width - 18)
                text: "~/.local/state/quickshell/shell-settings.json"
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontCaption
                color: Theme.textFaint
                elide: Text.ElideMiddle
            }

            Row {
                id: configActions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                SettingsAction {
                    text: "Open"
                    glyph: ""
                    onTriggered: page.openConfig()
                }

                SettingsAction {
                    text: "Reset all"
                    glyph: "↺"
                    danger: true
                    onTriggered: Settings.resetAll()
                }
            }
        }
    }
}
