import QtQuick
import "../Common"

// The slim glyph button the T3 pages use for header navigation — Back, Open
// in browser, the ⋯ menu. Extracted from T3ThreadPage so the New-thread
// header shares it instead of growing another near-identical inline copy
// (ActionButton.qml tells the same story for the label pill).
Rectangle {
    id: iconButton
    property string glyph: ""
    property color tint: Theme.textMid
    // A glyph is not a label. Every call site names itself, because a
    // focus ring on an unnamed arrow is worse than no focus ring.
    property string accessibleName: ""
    signal triggered()

    Accessible.role: Accessible.Button
    Accessible.name: iconButton.accessibleName
    Accessible.onPressAction: iconButton.triggered()

    width: 26
    height: Theme.controlHeight
    radius: 7
    color: Theme.hoverFill
    opacity: enabled ? 1 : 0.4
    activeFocusOnTab: enabled && visible
    border.width: activeFocus ? 1 : 0
    border.color: Theme.accent

    Keys.onPressed: event => {
        if (!iconButton.enabled)
            return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            iconButton.triggered();
            event.accepted = true;
        }
    }

    StateLayer {
        anchors.fill: parent
        radius: parent.radius
        hovered: iconMouse.containsMouse && iconButton.enabled
        pressed: iconMouse.pressed
        focused: iconButton.activeFocus
        tint: iconButton.tint
    }

    Text {
        anchors.centerIn: parent
        text: iconButton.glyph
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontBody
        font.weight: Theme.weightSemibold
        color: iconButton.tint
    }

    MouseArea {
        id: iconMouse
        anchors.fill: parent
        enabled: iconButton.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: iconButton.triggered()
    }
}
