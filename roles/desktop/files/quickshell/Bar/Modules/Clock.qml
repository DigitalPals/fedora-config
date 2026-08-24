import QtQuick
import Quickshell
import ".."
import "../../Common"

// The clock, and the date when there is room for it. Content only: the centre
// pill around it owns the pointer and opens the notification centre.
//
BarModule {
    id: root

    moduleId: "clock"
    spacing: 0
    detailSaving: showDate ? clockDate.implicitWidth + dateSeparator.width : 0

    // Named once: the date and the space before it are one decision, and binding
    // the spacer to the date's `visible` would make it depend on effective
    // visibility rather than on the thing that actually decides.
    readonly property bool showDate: Settings.modOpts.clock.showDate && !compact

    // Its own tick, the way the notification centre and the settings preview
    // each keep theirs. It needs no `enabled` gate: the bar only instantiates
    // a module slot on a visible bar, so an unmapped output has no clock at
    // all rather than a disabled one.
    SystemClock {
        id: clock
        precision: Settings.modOpts.clock.seconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    AnimatedText {
        anchors.verticalCenter: parent.verticalCenter
        animateChange: !Settings.modOpts.clock.seconds
        text: Qt.formatDateTime(clock.date, Settings.clock24
            ? (Settings.modOpts.clock.seconds ? "HH:mm:ss" : "HH:mm")
            : (Settings.modOpts.clock.seconds ? "h:mm:ss AP" : "h:mm AP"))
        font.family: Theme.fontMenu
        font.pixelSize: Theme.barTextSize
        font.weight: Theme.weightBold
        font.letterSpacing: 0.3
        font.features: Theme.tabularNumberFeatures
        color: Theme.barTextHi
    }

    Divider {
        id: dateSeparator
        kind: "space"
        visible: root.showDate
    }

    Text {
        id: clockDate
        visible: root.showDate
        anchors.verticalCenter: parent.verticalCenter
        text: Qt.formatDateTime(clock.date, Settings.modOpts.clock.dateFormat)
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        font.weight: Theme.weightSemibold
        font.features: Theme.tabularNumberFeatures
        color: Theme.barTextMid
    }
}
