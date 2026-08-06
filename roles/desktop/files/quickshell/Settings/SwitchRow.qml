import QtQuick
import "../Common"

// [label 90][description fill][switch][undo 18] (design v2 behavior rows).
Item {
    id: root

    property string label
    property string description: ""
    property bool checked: false
    property bool dirty: false
    signal toggled(bool value)
    signal resetRequested()

    height: 28

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

    Text {
        anchors.left: labelText.right
        anchors.right: control.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: root.description
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        color: Theme.textDim
        elide: Text.ElideRight
    }

    SettingsSwitch {
        id: control
        anchors.right: undoSlot.left
        anchors.rightMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        checked: root.checked
        onToggled: value => root.toggled(value)
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
