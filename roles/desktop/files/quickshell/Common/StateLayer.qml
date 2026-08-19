import QtQuick

// Material state overlay shared by shell controls. It is intentionally visual
// only: the owning control keeps its MouseArea, focus semantics, and press
// scale while this component makes hover/focus/pressed strength consistent.
Rectangle {
    id: root

    property bool hovered: false
    property bool pressed: false
    property bool focused: false
    property color tint: Theme.textHi

    color: tint
    opacity: pressed || focused ? Theme.statePressedOpacity
        : hovered ? Theme.stateHoverOpacity : 0

    Behavior on opacity {
        NumberAnimation { duration: Theme.chipFadeDuration / 2 }
    }
}
