import QtQuick
import "../Common"

// [label 90][slider][mono value 44][undo 18] — the undo column is always
// reserved so the chip appearing never shifts the row (design v2).
Item {
    id: root

    property string label
    property alias value: slider.value
    property alias min: slider.min
    property alias max: slider.max
    property alias step: slider.step
    property alias dimmed: slider.dimmed
    property alias gradientTrack: slider.gradientTrack
    property string unit: "px"
    property bool dirty: false
    signal moved(real value)
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
        color: slider.dimmed ? Theme.textDim : Theme.textMid
    }

    SettingsSlider {
        id: slider
        anchors.left: labelText.right
        anchors.right: valueText.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        onMoved: value => root.moved(value)
    }

    Text {
        id: valueText
        anchors.right: undoSlot.left
        anchors.verticalCenter: parent.verticalCenter
        width: 44
        horizontalAlignment: Text.AlignRight
        text: Math.round(slider.value) + " " + root.unit
        font.family: Theme.fontMono
        font.pixelSize: Theme.fontCaption
        color: Theme.textMid
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
