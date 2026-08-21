pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../Common"

// The notification centre, opened by the centre pill.
//
// The redesign folds three panels into one: the date the clock was already
// showing, the forecast the weather segment was already showing, and the
// notifications themselves. They were three separate popovers hanging off
// three adjacent triggers, which meant the pointer had to hit the right third
// of one pill to get the panel it wanted.
//
// The calendar and weather cards are drawn here; the notification list is the
// existing centre, embedded rather than reimplemented — its grouping, its
// inline actions and its Do Not Disturb footer are all still the same code.
Surface {
    id: root

    implicitWidth: Theme.popWideWidth
    spacing: 10

    readonly property var now: clock.date
    readonly property int daysInMonth:
        new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate()
    // Monday-first offset of the 1st.
    readonly property int leadingBlanks:
        (new Date(now.getFullYear(), now.getMonth(), 1).getDay() + 6) % 7
    readonly property int cellCount:
        Math.ceil((leadingBlanks + daysInMonth) / 7) * 7

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ---- date + month ----------------------------------------------------
    Rectangle {
        width: parent.width
        implicitHeight: dateRow.implicitHeight + 24
        height: implicitHeight
        radius: Theme.cardRadius
        color: Theme.tile

        Behavior on color {
            ColorAnimation { duration: Theme.surfaceDuration }
        }

        Row {
            id: dateRow
            anchors.centerIn: parent
            width: parent.width - 28
            spacing: 16

            Column {
                id: bigDate
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    text: Qt.formatDateTime(root.now, "dddd").toUpperCase()
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontMicro
                    font.weight: Theme.weightSemibold
                    font.letterSpacing: 1.6
                    color: Theme.accent
                }

                Text {
                    text: root.now.getDate()
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontHero
                    font.weight: Theme.weightBold
                    font.features: Theme.tabularNumberFeatures
                    color: Theme.textHi
                }

                Text {
                    text: Qt.formatDateTime(root.now, "MMMM yyyy")
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontTiny
                    font.weight: Theme.weightBold
                    color: Theme.textMid
                }
            }

            Grid {
                id: monthGrid
                anchors.verticalCenter: parent.verticalCenter
                columns: 7
                width: parent.width - parent.spacing - bigDate.width
                rowSpacing: 1

                readonly property real cell: width / 7

                Repeater {
                    model: ["M", "T", "W", "T", "F", "S", "S"]

                    delegate: Text {
                        required property string modelData
                        width: monthGrid.cell
                        height: 15
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontMicro
                        font.weight: Theme.weightMedium
                        color: Theme.textFaint
                    }
                }

                Repeater {
                    model: root.cellCount

                    delegate: Item {
                        id: cell

                        required property int index
                        readonly property int day: index - root.leadingBlanks + 1
                        readonly property bool valid: day >= 1 && day <= root.daysInMonth
                        readonly property bool today: valid && day === root.now.getDate()

                        width: monthGrid.cell
                        height: 19

                        Rectangle {
                            anchors.centerIn: parent
                            width: 19
                            height: 19
                            radius: 10
                            visible: cell.today
                            color: Theme.accent
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: cell.valid
                            text: cell.day
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontMicro
                            font.weight: cell.today ? Theme.weightSemibold : Theme.weightRegular
                            font.features: Theme.tabularNumberFeatures
                            color: cell.today ? Theme.textOnAccent : Theme.textMid
                        }
                    }
                }
            }
        }
    }

    // ---- weather ---------------------------------------------------------
    Rectangle {
        visible: Weather.ready || Weather.offline
        width: parent.width
        implicitHeight: 68
        height: implicitHeight
        radius: Theme.cardRadius
        color: Theme.tile

        Behavior on color {
            ColorAnimation { duration: Theme.surfaceDuration }
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            Row {
                id: currentWeather

                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Sym {
                    anchors.verticalCenter: parent.verticalCenter
                    name: Weather.symbol(Weather.code, Weather.isDay)
                    size: Theme.fontDisplay
                    fill: 1
                    symWeight: 400
                    color: Weather.glyphColor(Weather.code, Weather.isDay)
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Row {
                        spacing: 6

                        Text {
                            anchors.baseline: conditionText.baseline
                            text: Weather.ready ? Weather.temp + "°" : "—"
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontProminent
                            font.weight: Theme.weightBold
                            font.features: Theme.tabularNumberFeatures
                            color: Theme.textHi
                        }

                        Text {
                            id: conditionText
                            text: Weather.ready ? Weather.condition : "unavailable"
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontTiny
                            font.weight: Theme.weightBold
                            color: Theme.textMid
                        }
                    }

                    Row {
                        spacing: 3

                        Sym {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "place"
                            size: Theme.iconTiny
                            fill: 1
                            color: Theme.accent
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Weather.offline ? Weather.place + " · offline" : Weather.place
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontMicro
                            font.weight: Theme.weightBold
                            color: Theme.textFaint
                        }
                    }
                }
            }

            Item {
                id: weatherDivider

                width: 1
                height: parent.height - 22
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    color: Theme.stroke
                }
            }

            Row {
                id: forecastRow

                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - currentWeather.width - weatherDivider.width
                    - parent.spacing * 2
                spacing: 0

                readonly property real dayWidth: width / Math.max(1, forecastRepeater.count)

                Repeater {
                    id: forecastRepeater

                    model: Weather.days.slice(1, 5)

                    delegate: Column {
                        id: forecastDay

                        required property var modelData

                        width: forecastRow.dayWidth
                        spacing: 2

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: forecastDay.modelData.day.toUpperCase()
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontMicro
                            font.weight: Theme.weightMedium
                            font.letterSpacing: 0.4
                            color: Theme.textFaint
                        }

                        Sym {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: Weather.symbol(forecastDay.modelData.code, true)
                            size: Theme.iconSmall + 2
                            fill: 1
                            symWeight: 400
                            color: Weather.glyphColor(forecastDay.modelData.code, true)
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: forecastDay.modelData.hi + "°/" + forecastDay.modelData.lo + "°"
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontMicro
                            font.weight: Theme.weightMedium
                            font.features: Theme.tabularNumberFeatures
                            color: Theme.textMid
                        }
                    }
                }
            }
        }
    }

    // ---- notifications ---------------------------------------------------
    // The existing centre, embedded: it brings its own header, grouping,
    // inline actions and Do Not Disturb footer. Nothing about how a
    // notification is drawn or dismissed changed with the redesign, so none of
    // it is reimplemented here.
    NotifsPopover {
        width: parent.width
        drawBackground: false
        padding: 0
    }
}
