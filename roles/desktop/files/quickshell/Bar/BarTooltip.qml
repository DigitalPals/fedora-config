import QtQuick
import "../Common"

Item {
    id: root

    property string text: ""
    // -1 left, 0 centered, 1 right.
    property int align: 0
    property bool ready: false
    // The module's shared pointer state, not a bare bool: a MouseArea on a
    // layer surface can miss its exit event, and a tooltip armed off that
    // stale value has nothing left to dismiss it. Taking the check as a typed,
    // required object means a raw `containsMouse` cannot reach here by
    // mistake, and that the tip agrees with the pill it hangs under — both
    // read the one answer.
    required property PointerCheck check
    readonly property bool activeHover: check.over

    width: tip.implicitWidth
    height: tip.implicitHeight
    z: 1000
    opacity: ready ? 1 : 0
    // Popouts.open stays a hard cut (see the Connections note below); only
    // hover-driven appearance eases.
    visible: text !== "" && !Popouts.open && opacity > 0.01

    Behavior on opacity {
        NumberAnimation { duration: Theme.chipFadeDuration; easing.type: Easing.OutCubic }
    }

    // Call sites place the tip 6px below their module (y: parent.height + 6);
    // with a bottom bar this shifts it to 6px above instead.
    transform: Translate {
        y: Settings.position === "bottom" && root.parent
            ? -(root.height + root.parent.height + 12) : 0
    }

    onActiveHoverChanged: {
        if (activeHover)
            delay.restart();
        else {
            delay.stop();
            ready = false;
        }
    }

    // Mapping the separate popout surface can prevent the bar MouseArea
    // from receiving its final exit event. Do not carry an armed tooltip
    // across either edge of that surface's lifetime: otherwise it reappears
    // at its old module as soon as the popout closes.
    Connections {
        target: Popouts

        function onOpenChanged() {
            delay.stop();
            root.ready = false;
        }
    }

    Timer {
        id: delay
        interval: 550
        onTriggered: root.ready = root.activeHover
    }

    Rectangle {
        id: tip
        implicitWidth: label.implicitWidth + 14
        implicitHeight: Theme.tooltipHeight
        radius: 6
        color: Theme.popBg
        border.width: 1
        border.color: Theme.popBorder

        Text {
            id: label
            anchors.centerIn: parent
            text: root.text
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: Theme.textMid
        }
    }
}
