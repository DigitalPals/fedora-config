import QtQuick
import "../Common"

// The accent-coloured action at the foot of a popover — "Network settings",
// "Admin console", "Clear all", "Open T3 Code".
//
// Four copies of the same ten lines, differing only in how far the hit area
// overhangs the text and, on one, the type size. Only one of the four set a
// pointer cursor and only one widened its hit area, so both are standard here.
Text {
    id: root

    // How far the clickable area extends past the glyphs. These are short
    // strings at caption size; a few pixels of overhang makes them reliably
    // clickable without moving anything.
    property real hitMargin: 4

    signal clicked()

    font.family: Theme.fontMenu
    font.pixelSize: Theme.fontSecondary
    font.weight: Theme.weightMedium
    color: linkMouse.containsMouse ? Theme.accentHover : Theme.accent

    MouseArea {
        id: linkMouse
        anchors.fill: parent
        anchors.margins: -root.hitMargin
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
