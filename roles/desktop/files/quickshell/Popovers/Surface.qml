import QtQuick
import QtQuick.Effects
import "../Common"

// Shared popover surface: 360px wide, #16171c, 14px radius, hairline
// border, soft 48px shadow, 8px inner gutter.
Item {
    id: root

    property int padding: 8
    // The popover host draws the surface itself when morphing the modal
    // out of the bar; it disables this to avoid a doubled background.
    property bool drawBackground: true
    default property alias content: column.data

    implicitWidth: Theme.popWidth
    implicitHeight: column.implicitHeight + padding * 2

    RectangularShadow {
        visible: root.drawBackground
        anchors.fill: bg
        radius: bg.radius
        blur: 48
        spread: 0
        offset.y: 16
        color: Qt.rgba(0, 0, 0, 0.55)
    }

    Rectangle {
        id: bg
        visible: root.drawBackground
        anchors.fill: parent
        radius: Theme.popRadius
        color: Theme.popBg
        border.width: 1
        border.color: Theme.popBorder
    }

    Column {
        id: column
        x: root.padding
        y: root.padding
        width: parent.width - root.padding * 2
    }
}
