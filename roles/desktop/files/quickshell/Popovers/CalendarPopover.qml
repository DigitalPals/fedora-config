pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../Common"

Surface {
    id: root

    property int monthOffset: 0
    readonly property var now: clock.date
    readonly property var shown: new Date(now.getFullYear(), now.getMonth() + monthOffset, 1)

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Big time + date header
    Row {
        spacing: 10
        leftPadding: 12
        topPadding: 10
        bottomPadding: 4

        Text {
            text: Qt.formatDateTime(root.now, "HH:mm")
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontDisplay
            font.weight: Theme.weightSemibold
            color: Theme.textHi
        }

        Text {
            anchors.baseline: parent.children[0].baseline
            text: Qt.formatDateTime(root.now, "dddd, MMMM d")
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontBody
            color: Theme.textLow
        }
    }

    // Month navigation
    Item {
        width: parent.width
        height: Theme.rowHeight

        Text {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(root.shown, "MMMM yyyy")
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontBody
            font.weight: Theme.weightSemibold
            color: Theme.textMid
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Repeater {
                model: [{ g: "\uf053", d: -1 }, { g: "\uf054", d: 1 }]

                delegate: Rectangle {
                    required property var modelData
                    width: Theme.controlHeight
                    height: Theme.controlHeight
                    radius: 6
                    color: navMouse.containsMouse ? Theme.hoverFillStrong : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData.g
                        font.family: Theme.fontIcon
                        font.pixelSize: Theme.fontCaption
                        color: navMouse.containsMouse ? Theme.textHi : Theme.textLow
                    }

                    MouseArea {
                        id: navMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.monthOffset += parent.modelData.d
                    }
                }
            }
        }
    }

    // Day-of-week header + day grid (Monday first)
    Grid {
        columns: 7
        width: parent.width - 16
        x: 8

        Repeater {
            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

            delegate: Text {
                required property string modelData
                width: (root.width - 32) / 7
                height: Theme.calendarCellSize
                text: modelData
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSecondary
                font.weight: Theme.weightMedium
                color: Theme.textFaint
            }
        }

        Repeater {
            model: 42

            delegate: Item {
                id: day

                required property int index
                readonly property var cell: {
                    const first = root.shown;
                    const startOffset = (first.getDay() + 6) % 7; // Monday-first
                    return new Date(first.getFullYear(), first.getMonth(), 1 - startOffset + index);
                }
                readonly property bool inMonth: cell.getMonth() === root.shown.getMonth()
                readonly property bool isToday: cell.toDateString() === root.now.toDateString()

                width: (root.width - 32) / 7
                height: Theme.calendarCellSize

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 2
                    height: Theme.calendarCellSize
                    radius: Theme.chipRadius
                    color: day.isToday ? Theme.accent : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: day.cell.getDate()
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSecondary
                        font.weight: day.isToday ? Theme.weightSemibold : Theme.weightRegular
                        // Adjacent-month dates are still content, not decoration.
                        color: day.isToday ? Theme.accentFg : day.inMonth ? Theme.textMid : Theme.textFaint
                    }
                }
            }
        }
    }

    Item {
        width: 1
        height: 6
    }
}
