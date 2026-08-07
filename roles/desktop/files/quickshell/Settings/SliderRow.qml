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
    property alias hueTrack: slider.hueTrack
    property string unit: "px"
    property bool dirty: false
    readonly property bool narrow: width < 440
    readonly property int labelWidth: Settings.font === "mono" ? 104 : 90
    signal moved(real value)
    signal resetRequested()

    height: narrow ? 52 : 32

    Text {
        id: labelText
        anchors.left: parent.left
        y: root.narrow ? 0 : (parent.height - height) / 2
        width: root.narrow ? parent.width - 100 : root.labelWidth
        text: root.label
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        color: slider.dimmed ? Theme.textDim : Theme.textMid
    }

    SettingsSlider {
        id: slider
        x: root.narrow ? 0 : root.labelWidth
        y: root.narrow ? 23 : (parent.height - height) / 2
        width: root.narrow ? parent.width : valueText.x - x - 10
        accessibleName: root.label
        onMoved: value => root.moved(value)
    }

    Text {
        id: valueText
        anchors.right: undoSlot.left
        y: root.narrow ? 0 : (parent.height - height) / 2
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
        width: 28
        height: 28

        UndoChip {
            visible: root.dirty
            onClicked: root.resetRequested()
        }
    }
}
