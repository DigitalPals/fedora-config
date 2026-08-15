import QtQuick
import "../Common"

// The mark between two modules sharing one pill. A hairline inside a chip or
// status group, a dot inside the centre pill — the design uses the dot only
// where the two sides are one continuous sentence (time · date · weather).
Item {
    id: root

    // "rule" | "dot"
    property string kind: "rule"

    width: kind === "dot" ? 9 : 11
    height: Theme.chipHeight
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    Rectangle {
        anchors.centerIn: parent
        width: root.kind === "dot" ? 3 : 1
        height: root.kind === "dot" ? 3 : 13
        radius: root.kind === "dot" ? 1.5 : 0
        color: root.kind === "dot" ? Theme.dotDim : Theme.stroke
    }
}
