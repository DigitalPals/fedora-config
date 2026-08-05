import QtQuick
import "../Common"

Item {
    id: root

    property bool checked: false
    signal toggled(bool value)

    width: 44
    height: Theme.controlHeight

    Rectangle {
        id: track
        anchors.centerIn: parent
        width: 34
        height: 20
        radius: 10
        color: root.checked ? Theme.accent : Qt.rgba(1, 1, 1, 0.12)

        Rectangle {
            x: root.checked ? parent.width - width - 2 : 2
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            radius: 8
            color: root.checked ? Theme.accentFg : Theme.textLow
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.toggled(!root.checked)
    }
}
