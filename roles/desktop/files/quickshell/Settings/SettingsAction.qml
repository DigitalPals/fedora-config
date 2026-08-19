import QtQuick
import QtQuick.Controls as Controls
import "../Common"

Rectangle {
    id: root

    property string text: ""
    property string glyph: ""
    property bool compact: false
    property bool danger: false
    signal triggered()

    width: compact ? 30 : actionRow.implicitWidth + 16
    height: 30
    radius: Theme.rowRadius
    color: "transparent"
    border.width: activeFocus ? 1 : 0
    border.color: danger ? Theme.red : Theme.accent
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: root.text
    Accessible.onPressAction: root.triggered()
    Controls.ToolTip.visible: mouse.containsMouse && (root.compact || root.text.indexOf("Reset") === 0)
    Controls.ToolTip.text: root.text

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            root.triggered(); event.accepted = true;
        }
    }

    StateLayer {
        anchors.fill: parent
        radius: parent.radius
        hovered: mouse.containsMouse
        pressed: mouse.pressed
        focused: root.activeFocus
        tint: root.danger ? Theme.red : Theme.textHi
    }

    Row {
        id: actionRow
        anchors.centerIn: parent
        spacing: 6

        Text {
            text: root.glyph
            font.family: root.glyph === "↺" || root.glyph === "×"
                ? Theme.fontMenu : Theme.fontIcon
            font.pixelSize: Theme.fontSecondary
            color: root.danger ? Theme.redText : Theme.textMid
        }
        Text {
            visible: !root.compact
            text: root.text
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.weightMedium
            color: root.danger ? Theme.redText : Theme.textMid
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus();
            root.triggered();
        }
    }
}
