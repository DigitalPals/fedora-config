pragma ComponentBehavior: Bound
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

    // One rectangle per block, coloured by the side of the fill boundary it
    // sits on, plus a single rectangle for the block the boundary bisects.
    // The strip used to be built twice — a track row under a clipped fill row
    // — which cost 2N items for the same pixels; the Control Center alone
    // instantiated ~380 of them on every open.
    readonly property int pitch: Math.max(1, root.blockWidth + root.gap)
    readonly property int blocks: Math.max(0, Math.ceil(root.width / root.pitch))
    readonly property int fillWidth: Math.round(
        Math.max(0, Math.min(1, root.value)) * root.width)
    // Filled width of the bisected block; 0 when the boundary falls in a gap
    // or exactly on a block edge, in which case no partial block is drawn.
    readonly property int partialWidth: {
        const into = root.fillWidth - Math.floor(root.fillWidth / root.pitch) * root.pitch;
        return into > 0 && into < root.blockWidth ? into : 0;
    }

    Repeater {
        model: root.blocks

        Rectangle {
            id: block
            required property int index

            x: block.index * root.pitch
            width: root.blockWidth
            height: root.height
            color: block.x + block.width <= root.fillWidth ? root.fillColor : root.trackColor
        }
    }

    Rectangle {
        visible: root.partialWidth > 0
        x: root.fillWidth - root.partialWidth
        width: root.partialWidth
        height: root.height
        color: root.fillColor
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
