import QtQuick
import "../Common"

// Compact switch at the settings scale (design v2: 26×14 rows, 22×12 in the
// module list) — deliberately smaller than the popover Toggle.
Item {
    id: root

    property int trackWidth: 26
    property int trackHeight: 14
    property bool checked: false
    signal toggled(bool value)

    width: trackWidth
    height: trackHeight

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Theme.accent : Qt.rgba(1, 1, 1, 0.12)
    }

    Rectangle {
        x: root.checked ? root.trackWidth - width - 2 : 2
        anchors.verticalCenter: parent.verticalCenter
        width: root.trackHeight - 4
        height: root.trackHeight - 4
        radius: height / 2
        color: root.checked ? Theme.accentFg : Theme.textLow

        Behavior on x {
            NumberAnimation {
                duration: Theme.popoutContentFadeDuration
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.toggled(!root.checked)
    }
}
