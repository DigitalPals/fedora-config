import QtQuick
import "../Common"

// The one section mark in the shell's dialogs: an uppercase label, its
// conditional undo chip, and a hairline running from there to the edge —
// the same shape the menubar uses to separate one run of modules from the
// next, and the same one T3's inbox groups already draw.
Item {
    id: root

    property string label
    property bool dirty: false
    signal resetRequested()

    width: parent ? parent.width : 0
    height: Theme.sectionHeaderHeight

    Text {
        id: labelText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontMicro
        font.weight: Theme.weightSemibold
        font.letterSpacing: 1
        color: Theme.textFaint
    }

    UndoChip {
        id: undo
        anchors.left: labelText.right
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        visible: root.dirty
        onClicked: root.resetRequested()
    }

    Rectangle {
        anchors.left: root.dirty ? undo.right : labelText.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: Theme.hairlineSoft
    }
}
