import QtQuick
import "../Common"

Item {
    id: root

    property string text: ""
    property bool hovered: false
    // -1 left, 0 centered, 1 right.
    property int align: 0
    property bool ready: false

    width: tip.implicitWidth
    height: tip.implicitHeight
    z: 1000
    visible: ready && text !== "" && !Popouts.open

    // Call sites place the tip 6px below their module (y: parent.height + 6);
    // with a bottom bar this shifts it to 6px above instead.
    transform: Translate {
        y: Settings.position === "bottom" && root.parent
            ? -(root.height + root.parent.height + 12) : 0
    }

    onHoveredChanged: {
        if (hovered)
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
        onTriggered: root.ready = root.hovered
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
