pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.UPower
import "../Common"
import "../Common/StatusHelpers.js" as StatusHelpers

Surface {
    id: root

    readonly property var battery: UPower.displayDevice
    readonly property real pct: StatusHelpers.batteryPercent(battery)
    // Shared with the bar chip, which draws "charging" and "full" the same
    // way while this view names them apart.
    readonly property string chargeState: StatusHelpers.chargeState(battery)
    readonly property bool charging: chargeState === "charging"
    readonly property bool full: chargeState === "full"

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

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                anchors.baseline: percent.baseline
                text: Math.round(root.pct)
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontDisplay
                font.weight: Theme.weightSemibold
                color: Theme.textHi
            }

            Text {
                id: percent
                text: "%"
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontBody
                color: Theme.textLow
            }
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
                    font.pixelSize: Theme.fontSecondary
                    color: Theme.accent
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.full ? "Fully charged" : root.charging ? "Charging" : "On battery"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontBody
                    font.weight: Theme.weightMedium
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
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontSecondary
                color: Theme.textLow
            }
        }
    }

    // Charge bar
    Item {
        width: parent.width
        height: Theme.controlHeight

        BlockMeter {
            x: 12
            width: parent.width - 24
            anchors.verticalCenter: parent.verticalCenter
            height: 10
            value: root.pct / 100
            fillColor: root.pct <= 10 && !root.charging ? Theme.red : root.pct <= 20 && !root.charging ? Theme.amber : Theme.accent
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
                height: Theme.controlHeight
                radius: 8
                color: current ? Theme.accent : profMouse.containsMouse ? Theme.hoverFillStrong : Theme.cardFill

                Text {
                    anchors.centerIn: parent
                    text: parent.modelData.label
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontSecondary
                    font.weight: parent.current ? Theme.weightSemibold : Theme.weightMedium
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
