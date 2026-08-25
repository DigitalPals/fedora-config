import QtQuick
import "../Common"

// Shared popover surface: semantic width, the bar's own corner, a hairline
// border and a comfortable inner gutter. A panel sits on the shell's deepest
// surface rather than on a lighter card stacked over it — everything inside is
// separated by hairlines and space instead.
//
// The popout host normally paints the card itself and clears `drawBackground`,
// so what this contributes there is the layout and the padding. The background
// below is for a panel drawn anywhere else.
PopoutPanel {
    id: root

    property int padding: Theme.panelPadding
    property alias spacing: column.spacing
    default property alias content: column.data

    implicitWidth: Theme.popWidth
    implicitHeight: column.implicitHeight + padding * 2

    Rectangle {
        id: bg
        visible: root.drawBackground
        anchors.fill: parent
        radius: Theme.panelRadius
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
        spacing: Theme.panelSectionSpacing
    }
}
