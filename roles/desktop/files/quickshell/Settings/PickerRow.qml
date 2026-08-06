import QtQuick
import "../Common"

// [label 90][pills][caption fill, right][undo 18] (design v2 format rows).
Item {
    id: root

    property string label
    property alias model: pills.model
    property alias current: pills.current
    property alias mono: pills.mono
    property string caption: ""
    property bool captionMono: true
    property bool dirty: false
    signal picked(var value)
    signal resetRequested()

    height: 24

    Text {
        id: labelText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 90
        text: root.label
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        color: Theme.textMid
    }

    PillRow {
        id: pills
        anchors.left: labelText.right
        anchors.verticalCenter: parent.verticalCenter
        onPicked: value => root.picked(value)
    }

    Text {
        anchors.left: pills.right
        anchors.leftMargin: 10
        anchors.right: undoSlot.left
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: root.caption
        font.family: root.captionMono ? Theme.fontMono : Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        color: Theme.textFaint
        elide: Text.ElideLeft
    }

    Item {
        id: undoSlot
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        height: 16

        UndoChip {
            visible: root.dirty
            onClicked: root.resetRequested()
        }
    }
}
