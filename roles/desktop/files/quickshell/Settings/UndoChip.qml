import QtQuick
import "../Common"

// Small undo affordance beside a section header or row; the caller shows it
// only while the covered settings differ from their defaults (design v2).
Item {
    id: root

    signal clicked()

    width: 28
    height: 28
    activeFocusOnTab: visible

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            root.clicked(); event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 5
        color: mouse.pressed ? Theme.hoverFillStrong
            : mouse.containsMouse || root.activeFocus ? Theme.hoverFill : "transparent"
        border.width: root.activeFocus ? 1 : 0
        border.color: Theme.accent
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
        cursorShape: Qt.PointingHandCursor
        onClicked: { root.forceActiveFocus(); root.clicked(); }
    }
}
