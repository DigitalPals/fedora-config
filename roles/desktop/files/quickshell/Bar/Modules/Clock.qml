import QtQuick
import Quickshell
import ".."
import "../../Common"

// The clock, and the date when there is room for it. Content only: the centre
// pill around it owns the pointer and opens the notification centre.
//
// Do-not-disturb and idle-inhibit ride here as marks that slide out of zero
// width. Putting them in the clock rather than giving each a module of its own
// is what the redesign is doing: two states that change rarely, shown where
// the eye already goes, instead of two more permanent icons in the tray.
BarModule {
    id: root

    moduleId: "clock"
    spacing: 0
    detailSaving: showDate ? clockDate.implicitWidth + dateSeparator.width : 0

    // Named once: the date and the dot before it are one decision, and binding
    // the dot to the date's `visible` would make it depend on effective
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

    // A state mark that takes no space while the state is off.
    component StateMark: Item {
        id: mark

        property string glyph
        property bool on: false

        width: on ? Theme.iconSmall + 6 : 0
        height: Theme.iconSmall + 2
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        clip: true
        opacity: on ? 1 : 0

        Behavior on width {
            NumberAnimation {
                duration: Theme.expandDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.springCurve
            }
        }

        Behavior on opacity {
            NumberAnimation { duration: Theme.chipFadeDuration }
        }

        Sym {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            name: mark.glyph
            size: Theme.iconSmall + 1
            fill: 1
            color: Theme.accent
        }
    }

    StateMark {
        glyph: "do_not_disturb_on"
        on: Settings.notifDnd
    }

    StateMark {
        glyph: "coffee"
        on: SysInfo.idleInhibited
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Qt.formatDateTime(clock.date, Settings.clock24
            ? (Settings.modOpts.clock.seconds ? "HH:mm:ss" : "HH:mm")
            : (Settings.modOpts.clock.seconds ? "h:mm:ss AP" : "h:mm AP"))
        font.family: Theme.fontMenu
        font.pixelSize: Theme.barTextSize
        font.weight: Theme.weightBold
        font.letterSpacing: 0.3
        font.features: Theme.tabularNumberFeatures
        color: Theme.textHi
    }

    Divider {
        id: dateSeparator
        kind: "dot"
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
        color: Theme.textMid
    }
}
