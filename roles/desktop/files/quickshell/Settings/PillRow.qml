pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

// Wrapping segmented control with roving keyboard selection.
Flow {
    id: root

    property var model: []
    property var current
    property bool mono: false
    property int pillHeight: 24
    property int padH: 11
    signal picked(var value)
    readonly property bool anySelected: model.some(item => item.value === current)

    spacing: 6
    Repeater {
        id: pillRepeater
        model: root.model

        delegate: Rectangle {
            id: pill

            required property var modelData
            required property int index
            readonly property bool selected: modelData.value === root.current

            width: pillText.implicitWidth + root.padH * 2
            height: root.pillHeight
            radius: height / 2
            color: pill.selected ? Theme.accentAlpha(0.16)
                : pillMouse.pressed ? Theme.hoverFillStrong
                : pillMouse.containsMouse || activeFocus ? Theme.hoverFill : Theme.cardFill
            border.width: activeFocus ? 1 : 0
            border.color: Theme.accent
            activeFocusOnTab: pill.selected || (!root.anySelected && index === 0)
            Accessible.role: Accessible.RadioButton
            Accessible.name: pill.modelData.label
            Accessible.checked: pill.selected
            Accessible.onPressAction: root.picked(pill.modelData.value)

            Keys.onPressed: event => {
                let next = -1;
                if (event.key === Qt.Key_Left || event.key === Qt.Key_Up)
                    next = Math.max(0, index - 1);
                else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down)
                    next = Math.min(root.model.length - 1, index + 1);
                else if (event.key === Qt.Key_Home)
                    next = 0;
                else if (event.key === Qt.Key_End)
                    next = root.model.length - 1;
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                        || event.key === Qt.Key_Space) {
                    root.picked(modelData.value); event.accepted = true; return;
                }
                if (next >= 0) {
                    root.picked(root.model[next].value);
                    pillRepeater.itemAt(next).forceActiveFocus();
                    event.accepted = true;
                }
            }

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
                id: pillMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    pill.forceActiveFocus();
                    root.picked(pill.modelData.value);
                }
            }
        }
    }
}
