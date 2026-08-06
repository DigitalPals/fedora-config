import QtQuick
import "../Common"

// Segmented pill control (the prototype's seg()): one selected value, no
// hover state by design.
Row {
    id: root

    property var model: []
    property var current
    property bool mono: false
    property int pillHeight: 24
    property int padH: 11
    signal picked(var value)

    spacing: 6
    height: pillHeight

    Repeater {
        model: root.model

        delegate: Rectangle {
            id: pill

            required property var modelData
            readonly property bool selected: modelData.value === root.current

            anchors.verticalCenter: parent.verticalCenter
            width: pillText.implicitWidth + root.padH * 2
            height: root.pillHeight
            radius: height / 2
            color: pill.selected ? Theme.accentAlpha(0.16) : Theme.cardFill

            Text {
                id: pillText
                anchors.centerIn: parent
                text: pill.modelData.label
                font.family: root.mono ? Theme.fontMono : Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                font.weight: Theme.weightMedium
                color: pill.selected ? Theme.textHi : Theme.textLow
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.picked(pill.modelData.value)
            }
        }
    }
}
