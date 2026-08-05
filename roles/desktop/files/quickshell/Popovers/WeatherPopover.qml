import QtQuick
import "../Common"

// Weather popover (design 1g): current conditions header, five-day
// forecast as blocked range bars on the week's temperature span.
Surface {
    id: root

    implicitWidth: Theme.popWidth
    padding: Theme.surfacePadding
    spacing: 8

    readonly property int weekLo: Weather.days.reduce((m, d) => Math.min(m, d.lo), 99)
    readonly property int weekHi: Weather.days.reduce((m, d) => Math.max(m, d.hi), -99)
    readonly property real weekSpan: Math.max(1, weekHi - weekLo)

    // ---- Current conditions ------------------------------------------
    Item {
        width: parent.width
        height: Theme.rowHeight

        Row {
            x: 6
            y: 6
            spacing: 10

            Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                text: Weather.glyph(Weather.code, Weather.isDay)
                font.family: Theme.fontIcon
                font.pixelSize: Theme.fontDisplay
                color: Weather.glyphColor(Weather.code, Weather.isDay)
            }

            Text {
                text: Weather.temp + "°"
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontDisplay
                font.weight: Theme.weightSemibold
                color: Theme.textHi
            }

            Column {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 3
                spacing: 1

                Text {
                    text: Weather.condition + " · feels " + Weather.feels + "°"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontBody
                    font.weight: Theme.weightMedium
                    color: Theme.textMid
                }

                Text {
                    text: Weather.place + " · " + Weather.windDir + " " + Weather.windKmh + " km/h · " + Weather.humidity + "% humidity"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textDim
                }
            }
        }
    }

    // ---- Five-day forecast -------------------------------------------
    Rectangle {
        width: parent.width
        radius: 10
        color: Theme.cardFill
        height: forecastCol.implicitHeight + 20

        Column {
            id: forecastCol
            x: 12
            y: 10
            width: parent.width - 24
            spacing: 7

            Repeater {
                model: Weather.days

                delegate: Item {
                    id: dayRow

                    required property var modelData

                    width: forecastCol.width
                    height: Math.max(dayLabel.implicitHeight, dayGlyph.implicitHeight,
                        loHi.implicitHeight)

                    Text {
                        id: dayLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: dayRow.modelData.day
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontCaption
                        font.weight: Theme.weightSemibold
                        color: Theme.textLow
                    }

                    // Daily codes summarise a whole day, so always the day
                    // variant of the icon.
                    Text {
                        id: dayGlyph
                        x: 34
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.glyph(dayRow.modelData.code, true)
                        font.family: Theme.fontIcon
                        font.pixelSize: Theme.fontBody
                        color: Weather.glyphColor(dayRow.modelData.code, true)
                    }

                    Item {
                        id: range
                        x: 56
                        width: parent.width - 56 - loHi.implicitWidth - 8
                        height: 6
                        anchors.verticalCenter: parent.verticalCenter

                        BlockMeter {
                            anchors.fill: parent
                            value: 0
                            blockWidth: 3
                            gap: 2
                        }

                        BlockMeter {
                            x: Math.round((dayRow.modelData.lo - root.weekLo) / root.weekSpan * range.width)
                            width: Math.max(5, Math.round((dayRow.modelData.hi - dayRow.modelData.lo) / root.weekSpan * range.width))
                            height: parent.height
                            value: 1
                            blockWidth: 3
                            gap: 2
                            trackColor: "transparent"
                            fillColor: dayRow.modelData.hi >= 25 ? Theme.amber : Theme.accent
                        }
                    }

                    Text {
                        id: loHi
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.RichText
                        text: `${dayRow.modelData.lo}° <font color="${Theme.textDim}">/</font> ${dayRow.modelData.hi}°`
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontCaption
                        color: Theme.textMid
                    }
                }
            }
        }
    }

    // ---- Footer --------------------------------------------------------
    Item {
        width: parent.width
        height: Theme.controlHeight

        Text {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            text: "open-meteo"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: Theme.textDim
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.RichText
            text: Weather.updatedAt > 0
                ? `updated <font color="${Theme.textLow}" face="${Theme.fontMono}">${Qt.formatTime(new Date(Weather.updatedAt), "HH:mm")}</font>`
                : "loading…"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: Theme.textDim
        }
    }
}
