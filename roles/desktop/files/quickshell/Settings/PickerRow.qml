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
    readonly property bool narrow: width < 440
    readonly property int labelWidth: Settings.font === "mono" ? 122 : 90
    readonly property real captionWidth: caption === "" ? 0
        : Math.min(180, captionText.implicitWidth)
    signal picked(var value)
    signal resetRequested()

    height: narrow ? 58 : 32

    Text {
        id: labelText
        anchors.left: parent.left
        y: root.narrow ? 0 : (parent.height - height) / 2
        width: root.narrow ? parent.width - 130 : root.labelWidth
        text: root.label
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        color: Theme.textMid
    }

    PillRow {
        id: pills
        x: root.narrow ? 0 : root.labelWidth
        y: root.narrow ? 29 : (parent.height - height) / 2
        width: root.narrow ? parent.width
            : Math.max(100, parent.width - x - undoSlot.width
                - root.captionWidth - (root.captionWidth > 0 ? 10 : 0))
        onPicked: value => root.picked(value)
    }

    Text {
        id: captionText
        y: root.narrow ? 0 : (parent.height - height) / 2
        x: root.narrow ? Math.max(labelText.width, parent.width - implicitWidth - undoSlot.width - 6)
            : undoSlot.x - root.captionWidth
        width: root.narrow ? Math.max(0, undoSlot.x - x - 4) : root.captionWidth
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
        width: 28
        height: 28

        UndoChip {
            visible: root.dirty
            onClicked: root.resetRequested()
        }
    }
}
