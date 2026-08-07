import QtQuick
import ".."
import "../../Common"

// Quiet weather chip next to the clock (design 1g).
    BarModule {
        id: weatherModule

    moduleId: "weather"
        spacing: 3
        // An enabled weather module stays on the bar while it is
        // offline: a chip that vanishes cannot say why. Only the
        // gap before the first forecast lands is blank.
        readonly property bool shown: Weather.ready || Weather.offline
        visible: shown
        detailSaving: weatherCondition.implicitWidth + 5

        Divider {
            visible: weatherModule.dividerBefore && weatherModule.shown
        }

// Quiet weather chip next to the clock (design 1g).
BarChip {
    id: weatherChip
    visible: weatherModule.shown
    // One tighter than the default: the leading weather glyph
    // already carries its own side bearing.
    hPadding: 6
    spacing: 5
    host: weatherModule.host
    panelName: "weather"
    isle: weatherModule.isle
    // Offline is the one state the chip cannot spell out in the
    // width it has, so the reason goes here.
    tooltip: Weather.place + " · "
        + (Weather.offline ? Weather.fetchError : Weather.condition)

    // Weather.code is -1 until a forecast lands, and both glyph()
    // and glyphColor() already answer that with the na mark in
    // Theme.textDim — no fallback needed here.
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Weather.glyph(Weather.code, Weather.isDay)
        font.family: Theme.fontIcon
        font.pixelSize: Theme.barIconSize
        color: Weather.glyphColor(Weather.code, Weather.isDay)
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        // Weather.temp is 0 with nothing loaded, and "0°" is a
        // reading. A dash is not.
        text: Weather.ready ? Weather.temp + "°" : "—"
        font.family: Theme.fontMenu
        font.pixelSize: Theme.barTextSize
        font.weight: Theme.weightSemibold
        font.features: Theme.tabularNumberFeatures
        // Dimmed while offline, so a forecast that has stopped
        // being refreshed does not read as current.
        color: Weather.offline ? Theme.textFaint : Theme.textMid
    }

    Text {
        id: weatherCondition
        visible: !weatherModule.compact
        anchors.verticalCenter: parent.verticalCenter
        text: Weather.ready ? Weather.condition : "unavailable"
        font.family: Theme.fontMenu
        font.pixelSize: Theme.barTextSize
        color: weatherChip.held || weatherChip.hovered ? Theme.textMid : Theme.textLow

        Behavior on color {
            ColorAnimation { duration: Theme.chipFadeDuration }
        }
    }
}
    }
