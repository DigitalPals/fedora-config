import QtQuick
import "../Common"

// Shared popover surface: semantic width, the card's radius, a hairline
// border, a soft shadow and a comfortable inner gutter.
//
// The popout host normally paints the card itself and clears `drawBackground`,
// so what this contributes there is the layout and the padding. The background
// below is for a panel drawn anywhere else.
PopoutPanel {
    id: root

    property int padding: Theme.surfacePadding
    property alias spacing: column.spacing
    default property alias content: column.data

    implicitWidth: Theme.popWidth
    implicitHeight: column.implicitHeight + padding * 2

    Rectangle {
        id: bg
        visible: root.drawBackground
        anchors.fill: parent
        radius: Theme.popRadius
        color: root.surfaceColor
        border.width: 1
        border.color: root.surfaceBorderColor

        Behavior on color {
            ColorAnimation { duration: Theme.surfaceDuration }
        }
    }

    Column {
        id: column
        x: root.padding
        y: root.padding
        width: parent.width - root.padding * 2
        spacing: 10
    }
}
