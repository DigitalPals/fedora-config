import QtQuick
import "../Common"

// A transparent layout section of the unified menubar: the bar slab in
// Bar.qml draws the shared background, clusters only arrange modules.
Item {
    id: root

    property int padding: 8
    property int spacing: 1
    default property alias content: row.data

    implicitWidth: row.implicitWidth + padding * 2
    implicitHeight: Theme.barHeight

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        x: root.padding
        spacing: root.spacing
    }
}
