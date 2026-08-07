import QtQuick
import Quickshell
import ".."
import "../../Common"

// Clock, and the date when there is room for it. Opens the calendar.
BarModule {
    id: root

    moduleId: "clock"

    // Its own tick, the way CalendarPopover and the settings preview each
    // keep theirs. It needs no `enabled` gate: the bar only instantiates a
    // module slot on a visible bar, so an unmapped output has no clock at
    // all rather than a disabled one.
    SystemClock {
        id: clock
        precision: Settings.modOpts.clock.seconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    BarChip {
        id: clockChip
        readonly property real detailSaving: Settings.modOpts.clock.showDate
            ? clockDate.implicitWidth + 6 : 0

        host: root.host
        panelName: "calendar"
        isle: root.isle
        tooltip: Qt.formatDateTime(clock.date, "dddd, MMMM d")

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, Settings.clock24
                ? (Settings.modOpts.clock.seconds ? "HH:mm:ss" : "HH:mm")
                : (Settings.modOpts.clock.seconds ? "h:mm:ss AP" : "h:mm AP"))
            font.family: Theme.fontMenu
            font.pixelSize: Theme.barTextSize
            font.weight: Theme.weightSemibold
            font.features: Theme.tabularNumberFeatures
            color: Theme.textHi
        }

        Text {
            id: clockDate
            visible: Settings.modOpts.clock.showDate && !root.compact
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, Settings.modOpts.clock.dateFormat)
            font.family: Theme.fontMenu
            font.pixelSize: Theme.barTextSize
            font.features: Theme.tabularNumberFeatures
            color: clockChip.held || clockChip.hovered ? Theme.textMid : Theme.textLow

            Behavior on color {
                ColorAnimation { duration: Theme.chipFadeDuration }
            }
        }
    }
}
