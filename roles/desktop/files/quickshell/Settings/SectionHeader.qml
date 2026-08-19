import QtQuick
import "../Common"

// Uppercase section label with the conditional undo chip (design v2).
Row {
    id: root

    property string label
    property bool dirty: false
    signal resetRequested()

    spacing: 6
    height: 28

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        font.weight: Theme.weightSemibold
        font.letterSpacing: 0.6
        color: Theme.textDim
    }

    UndoChip {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.dirty
        onClicked: root.resetRequested()
    }
}
