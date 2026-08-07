import QtQuick
import "../Common"

// [label 90][description fill][switch][undo 18] (design v2 behavior rows).
Item {
    id: root

    property string label
    property string description: ""
    property bool checked: false
    property bool dirty: false
    readonly property bool narrow: width < 440
    readonly property int labelWidth: Settings.font === "mono" ? 104 : 90
    signal toggled(bool value)
    signal resetRequested()

    height: narrow ? 48 : 32

    Text {
        id: labelText
        anchors.left: parent.left
        y: root.narrow ? 2 : (parent.height - height) / 2
        width: root.narrow ? parent.width - 82 : root.labelWidth
        text: root.label
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        color: Theme.textMid
    }

    Text {
        x: root.narrow ? 0 : root.labelWidth
        y: root.narrow ? 24 : (parent.height - height) / 2
        width: root.narrow ? parent.width - 4 : control.x - x - 10
        text: root.description
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        color: Theme.textDim
        elide: root.narrow ? Text.ElideNone : Text.ElideRight
        wrapMode: root.narrow ? Text.Wrap : Text.NoWrap
        maximumLineCount: root.narrow ? 2 : 1
    }

    SettingsSwitch {
        id: control
        anchors.right: undoSlot.left
        anchors.rightMargin: 2
        y: root.narrow ? 0 : (parent.height - height) / 2
        checked: root.checked
        Accessible.name: root.label
        onToggled: value => root.toggled(value)
    }

    Item {
        id: undoSlot
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 28
        height: 28

        UndoChip {
            visible: root.dirty
            onClicked: root.resetRequested()
        }
    }
}
