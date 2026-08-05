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

    onHoveredChanged: {
        if (hovered)
            delay.restart();
        else {
            delay.stop();
            ready = false;
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
