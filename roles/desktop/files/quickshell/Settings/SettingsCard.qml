import QtQuick
import "../Common"

Rectangle {
    id: root
    default property alias content: contentItem.data
    property int padding: 12

    implicitHeight: 52
    radius: Theme.rowRadius
    color: Theme.cardFill

    Item {
        id: contentItem
        x: root.padding
        y: root.padding
        width: parent.width - root.padding * 2
        height: parent.height - root.padding * 2
    }
}
