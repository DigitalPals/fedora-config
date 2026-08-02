import QtQuick
import Quickshell.Services.UPower
import "../Common"

Surface {
    id: root

    readonly property var battery: UPower.displayDevice
    readonly property real pct: battery ? (battery.percentage <= 1 ? battery.percentage * 100 : battery.percentage) : 0
    readonly property bool charging: battery && (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.PendingCharge)
    readonly property bool full: battery && battery.state === UPowerDeviceState.FullyCharged

    function fmtDuration(secs) {
        if (!secs || secs <= 0)
            return "";
        const h = Math.floor(secs / 3600);
        const m = Math.round((secs % 3600) / 60);
        return h > 0 ? `${h} h ${String(m).padStart(2, "0")} min` : `${m} min`;
    }

    // Percentage + state
    Row {
        width: parent.width
        leftPadding: 10
        topPadding: 10
        bottomPadding: 6
        spacing: 12

        Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.RichText
            text: `<span style="font-size:26px">${Math.round(root.pct)}</span><span style="font-size:14px;color:${Theme.textLow}">%</span>`
            font.family: Theme.fontMono
            font.weight: 600
            color: Theme.textHi
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Row {
                spacing: 6

                Text {
                    visible: root.charging
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf0e7"
                    font.family: Theme.fontIcon
                    font.pixelSize: 11
                    color: Theme.accent
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.full ? "Fully charged" : root.charging ? "Charging" : "On battery"
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight: 500
                    color: Theme.textMid
                }
            }

            Text {
                visible: text !== ""
                text: {
                    if (!root.battery)
                        return "";
                    if (root.charging && root.battery.timeToFull > 0)
                        return root.fmtDuration(root.battery.timeToFull) + " until full";
                    if (!root.charging && !root.full && root.battery.timeToEmpty > 0)
                        return root.fmtDuration(root.battery.timeToEmpty) + " remaining";
                    return "";
                }
                font.family: Theme.fontSans
                font.pixelSize: 11
                color: Theme.textLow
            }
        }
    }

    // Charge bar
    Item {
        width: parent.width
        height: 18

        Rectangle {
            x: 12
            width: parent.width - 24
            anchors.verticalCenter: parent.verticalCenter
            height: 6
            radius: 3
            color: Qt.rgba(1, 1, 1, 0.08)

            Rectangle {
                width: parent.width * root.pct / 100
                height: parent.height
                radius: 3
                color: root.pct <= 10 && !root.charging ? Theme.red : root.pct <= 20 && !root.charging ? Theme.amber : Theme.accent
            }
        }
    }

    SectionLabel {
        text: "POWER PROFILE"
    }

    Row {
        width: parent.width
        leftPadding: 10
        rightPadding: 10
        topPadding: 2
        bottomPadding: 10
        spacing: 4

        Repeater {
            model: [
                { label: "Saver", profile: PowerProfile.PowerSaver, available: true },
                { label: "Balanced", profile: PowerProfile.Balanced, available: true },
                { label: "Performance", profile: PowerProfile.Performance, available: PowerProfiles.hasPerformanceProfile }
            ]

            delegate: Rectangle {
                required property var modelData
                readonly property bool current: PowerProfiles.profile === modelData.profile

                visible: modelData.available
                width: (root.width - 16 - 20 - 8) / 3
                height: 28
                radius: 8
                color: current ? Theme.accent : profMouse.containsMouse ? Theme.hoverFillStrong : Theme.cardFill

                Text {
                    anchors.centerIn: parent
                    text: parent.modelData.label
                    font.family: Theme.fontSans
                    font.pixelSize: 11
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
