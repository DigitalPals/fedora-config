import QtQuick
import "../Common"

// 4px track + 10px knob slider, design language from the audio/media popovers.
Item {
    id: root

    property real value: 0 // 0..1
    property bool dimmed: false
    signal moved(real value)

    height: Theme.controlHeight

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.08)
        opacity: root.dimmed ? 0.45 : 1

        Rectangle {
            width: Math.max(0, Math.min(1, root.value)) * parent.width
            height: parent.height
            radius: 2
            color: root.dimmed ? Theme.textLow : Theme.accent
        }
    }

    Rectangle {
        visible: !root.dimmed
        x: Math.max(0, Math.min(1, root.value)) * (parent.width - width)
        anchors.verticalCenter: parent.verticalCenter
        width: 10
        height: 10
        radius: 5
        color: Theme.textHi
    }

    MouseArea {
        anchors.fill: parent
        onPressed: mouse => root.moved(Math.max(0, Math.min(1, mouse.x / width)))
        onPositionChanged: mouse => {
            if (pressed)
                root.moved(Math.max(0, Math.min(1, mouse.x / width)));
        }
    }
}
