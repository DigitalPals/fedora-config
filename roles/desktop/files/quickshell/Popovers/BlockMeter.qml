import QtQuick
import "../Common"

// Shared "blocked" meter (Lumen language): a strip of fixed-width blocks
// with the filled fraction overlaid in color. One component for every
// level in the shell — usage windows, volume/brightness, CPU/RAM/temp.
Item {
    id: root

    property real value: 0 // 0..1
    property color fillColor: Theme.accent
    property color trackColor: Qt.rgba(1, 1, 1, 0.08)
    property int blockWidth: 4
    property int gap: 2
    property bool interactive: false
    signal moved(real value)

    implicitHeight: 10

    Row {
        spacing: root.gap

        Repeater {
            model: Math.max(0, Math.ceil(root.width / (root.blockWidth + root.gap)))

            Rectangle {
                width: root.blockWidth
                height: root.height
                color: root.trackColor
            }
        }
    }

    Item {
        width: Math.round(Math.max(0, Math.min(1, root.value)) * root.width)
        height: root.height
        clip: true

        Row {
            spacing: root.gap

            Repeater {
                model: Math.max(0, Math.ceil(root.width / (root.blockWidth + root.gap)))

                Rectangle {
                    width: root.blockWidth
                    height: root.height
                    color: root.fillColor
                }
            }
        }
    }

    MouseArea {
        visible: root.interactive
        anchors.fill: parent
        anchors.margins: -4
        onPressed: mouse => root.moved(Math.max(0, Math.min(1, mouse.x / root.width)))
        onPositionChanged: mouse => {
            if (pressed)
                root.moved(Math.max(0, Math.min(1, mouse.x / root.width)));
        }
    }
}
