import QtQuick
import ".."
import "../../Common"

// Weather gets its own forecast pill: a sky mark and the temperature, with the
// condition spelled out when the bar is wide enough.
//
// An enabled weather module stays on the bar while it is offline: a segment
// that vanishes cannot say why. Only the gap before the first forecast lands
// is blank, and that gate is the bar's auto-rule rather than this file's, so
// the space before the segment agrees with it.
BarModule {
    id: root

    moduleId: "weather"
    spacing: 5
    detailSaving: condition.implicitWidth + spacing

    BarChip {
        id: chip

        host: root.host
        panelName: "weather"
        isle: root.isle
        anchorItem: root.groupAnchor ?? chip
        spacing: 5
        tooltip: Weather.offline ? "Weather · offline" : "Weather"

        Sym {
            anchors.verticalCenter: parent.verticalCenter
            name: Weather.symbol(Weather.code, Weather.isDay)
            size: Theme.iconSmall + 1
            fill: 1
            // Weather.code is -1 until a forecast lands, and both symbol() and
            // barGlyphColor() already answer that with the "no data" mark in
            // Theme.barTextDim — no fallback needed here.
            color: Weather.barGlyphColor(Weather.code, Weather.isDay)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // Weather.temp is 0 with nothing loaded, and "0°" is a reading. A
            // dash is not.
            text: Weather.ready ? Weather.temp + "°" : "—"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.weightBold
            font.features: Theme.tabularNumberFeatures
            // Dimmed while offline, so a forecast that has stopped being
            // refreshed does not read as current.
            color: Weather.offline ? Theme.barTextFaint : Theme.barTextMid
        }

        Text {
            id: condition
            visible: !root.compact
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.ready ? Weather.condition : "unavailable"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.weightSemibold
            color: Theme.barTextLow
        }
    }
}
