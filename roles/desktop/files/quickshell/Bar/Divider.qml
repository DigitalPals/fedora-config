import QtQuick
import "../Common"

Item {
    width: 7
    height: Theme.barHeight
    anchors.verticalCenter: parent.verticalCenter

    Rectangle {
        anchors.centerIn: parent
        width: 1
        height: 12
        color: Theme.hairline
    }
}
