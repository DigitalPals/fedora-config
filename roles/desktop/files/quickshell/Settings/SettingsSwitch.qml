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

    width: Math.max(34, trackWidth)
    height: Math.max(28, trackHeight)
    activeFocusOnTab: true

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            root.toggled(!root.checked); event.accepted = true;
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: root.trackWidth
        height: root.trackHeight
        radius: height / 2
        color: root.checked ? Theme.accent : Qt.rgba(1, 1, 1, 0.12)
        border.width: root.activeFocus ? 1 : 0
        border.color: Theme.textHi
    }

    Rectangle {
        x: (root.width - root.trackWidth) / 2
            + (root.checked ? root.trackWidth - width - 2 : 2)
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
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus();
            root.toggled(!root.checked);
        }
    }
}
