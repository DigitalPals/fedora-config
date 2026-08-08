pragma ComponentBehavior: Bound
import QtQuick
// Still needed for the PowerProfile/PowerProfiles controls below;
// the battery reading itself comes from Common/Battery.qml.
import Quickshell.Services.UPower
import "../Common"
import "../Common/Format.js" as Format

Surface {
    id: root

    function fmtDuration(secs) {
        if (!secs || secs <= 0)
            return "";
        const h = Math.floor(secs / Format.HOUR);
        const m = Math.round((secs % Format.HOUR) / Format.MINUTE);
        return h > 0 ? `${h} h ${Format.pad2(m)} min` : `${m} min`;
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
                text: Math.round(Battery.percent)
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
                    visible: Battery.charging
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf0e7"
                    font.family: Theme.fontIcon
                    font.pixelSize: Theme.fontSecondary
                    color: Theme.accent
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Battery.full ? "Fully charged" : Battery.charging ? "Charging" : "On battery"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontBody
                    font.weight: Theme.weightMedium
                    color: Theme.textMid
                }
            }

            Text {
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
            value: Battery.percent / 100
            fillColor: Battery.percent <= 10 && !Battery.charging ? Theme.red : Battery.percent <= 20 && !Battery.charging ? Theme.amber : Theme.accent
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
                    cursorShape: Qt.PointingHandCursor
                    onClicked: PowerProfiles.profile = parent.modelData.profile
                }
            }
        }
    }
}
