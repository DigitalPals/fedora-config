import QtQuick
import Quickshell
import "../Common"
import "../Common/Format.js" as Format

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
            settingKey: "clock24"
            model: [{ value: true, label: "24 h" }, { value: false, label: "12 h" }]
            caption: Qt.formatDateTime(page.nowDate, Settings.clock24 ? "HH:mm" : "h:mm AP")
        }

        PickerRow {
            width: parent.width
            label: "Temperature"
            settingKey: "unit"
            model: [{ value: "c", label: "°C" }, { value: "f", label: "°F" }]
            caption: Weather.ready ? Weather.temp + "° outside" : ""
        }

        SliderRow {
            width: parent.width
            label: "Scroll speed"
            settingKey: "scrollFactor"
            resetLabel: "Touchpad scroll speed"
            min: 0.2
            max: 2.0
            step: 0.1
            decimals: 1
            unit: "×"
            dirty: Math.abs(Settings.scrollFactor - Settings.defaults.scrollFactor) > 0.001
        }

        SectionHeader {
            label: "NIGHT LIGHT"
        }

        SliderRow {
            width: parent.width
            label: "Warmth"
            settingKey: "warmth"
            min: 1900
            max: 4500
            step: 50
            unit: "K"
            gradientTrack: true
        }

        Text {
            width: parent.width
            leftPadding: page.width < Theme.settingsNarrowWidth ? 0 : Theme.settingsLabelWidth + 10
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
            settingKey: "osd"
            model: [{ value: "top", label: "Top center" }, { value: "bottom", label: "Bottom center" }]
            caption: "volume / brightness popup"
            captionMono: false
        }

        SectionHeader {
            label: "T3 USAGE"
        }

        PickerRow {
            width: parent.width
            label: "Poll every"
            settingKey: "pollMax"
            model: [{ value: 60, label: "1 min" }, { value: 300, label: "5 min" }, { value: 600, label: "10 min" }]
            caption: "next " + Format.mmss(page.pollLeft)
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
                    glyph: "open_in_new"
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
