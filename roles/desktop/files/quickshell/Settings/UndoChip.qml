import QtQuick
import "../Common"

// Small undo affordance beside a section header or row; the caller shows it
// only while the covered settings differ from their defaults (design v2).
Item {
    id: root

    signal clicked()

    width: 18
    height: 16

    Rectangle {
        anchors.fill: parent
        radius: 5
        color: mouse.containsMouse ? Theme.hoverFillStrong : "transparent"
    }

    Text {
        anchors.centerIn: parent
        text: "↺"
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        color: mouse.containsMouse ? Theme.textHi : Theme.textDim
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
