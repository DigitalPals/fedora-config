import QtQuick
import "../../Common"

// One quick-toggle tile in the Overview grid: glyph over label, lit while on.
// The lit state fills the glyph and hands both marks the accent — the tile
// fill itself stays a quiet chip step so four of them in a row cannot turn
// the drawer fluorescent.
Rectangle {
    id: root

    property string glyph: ""
    property string label: ""
    property bool on: false
    signal toggled()

    height: 54
    radius: 10
    color: on ? Theme.chipHover : Theme.chip
    activeFocusOnTab: true
    border.width: activeFocus ? 1 : 0
    border.color: Theme.accent
    Accessible.role: Accessible.CheckBox
    Accessible.checked: on
    Accessible.name: label
    Accessible.onToggleAction: root.toggled()

    Behavior on color {
        ColorAnimation { duration: Theme.chipFadeDuration }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            root.toggled();
            event.accepted = true;
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 5

        Sym {
            anchors.horizontalCenter: parent.horizontalCenter
            name: root.glyph
            size: 17
            fill: root.on ? 1 : 0
            color: root.on ? Theme.accent : Theme.textMid
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontMicro
            font.weight: Theme.weightSemibold
            color: root.on ? Theme.textHi : Theme.textMid
        }
    }

    StateLayer {
        anchors.fill: parent
        radius: parent.radius
        hovered: tileMouse.containsMouse
        pressed: tileMouse.pressed
        tint: Theme.textHi
        pressPoint: Qt.point(tileMouse.mouseX, tileMouse.mouseY)
    }

    MouseArea {
        id: tileMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus();
            root.toggled();
        }
    }
}
