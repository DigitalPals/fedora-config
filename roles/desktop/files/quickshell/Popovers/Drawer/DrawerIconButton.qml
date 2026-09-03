import QtQuick
import "../../Common"

// A 32px glyph button for the drawer's footers and inline actions. A glyph
// is not a label, so every call site names itself.
Rectangle {
    id: root

    property string glyph: ""
    property real fill: 0
    property real glyphSize: 17
    property color tint: Theme.textMid
    property string accessibleName: ""
    signal clicked()

    width: 32
    height: 32
    radius: Theme.rowRadius
    color: "transparent"
    opacity: enabled ? 1 : 0.4
    activeFocusOnTab: enabled && visible
    border.width: activeFocus ? 1 : 0
    border.color: Theme.accent
    Accessible.role: Accessible.Button
    Accessible.name: accessibleName
    Accessible.onPressAction: root.clicked()

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            root.clicked();
            event.accepted = true;
        }
    }

    StateLayer {
        anchors.fill: parent
        radius: parent.radius
        hovered: mouse.containsMouse
        pressed: mouse.pressed
        tint: Theme.textHi
        pressPoint: Qt.point(mouse.mouseX, mouse.mouseY)
    }

    Sym {
        anchors.centerIn: parent
        name: root.glyph
        size: root.glyphSize
        fill: root.fill
        color: mouse.containsMouse ? Theme.textHi : root.tint
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus();
            root.clicked();
        }
    }
}
