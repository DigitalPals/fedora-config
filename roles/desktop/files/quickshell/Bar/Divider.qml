import QtQuick
import "../Common"

// The separation between two modules sharing one pill. Chip and status groups
// draw a hairline; the centre group keeps the same breathing room without a
// visible mark.
Item {
    id: root

    // "rule" | "space"
    property string kind: "rule"

    width: kind === "space" ? 9 : 11
    height: Theme.chipHeight
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    Rectangle {
        visible: root.kind === "rule"
        anchors.centerIn: parent
        width: 1
        height: 13
        color: Theme.barStroke
    }
}
