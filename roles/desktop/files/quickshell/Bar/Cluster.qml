import QtQuick
import QtQuick.Effects
import "../Common"

Item {
    id: root

    readonly property bool isCluster: true

    // Fused popout state (design t5): the joined bottom corner squares
    // off so island and popout merge into one shape, and the island's own
    // shadow hands over to the popout's fused-shape shadow.
    property bool joinBL: false
    property bool joinBR: false
    property bool fused: false

    property int padding: 8
    property int spacing: 1
    default property alias content: row.data

    implicitWidth: row.implicitWidth + padding * 2
    implicitHeight: Theme.barHeight

    RectangularShadow {
        anchors.fill: bg
        radius: Theme.clusterRadius
        blur: 16
        spread: 0
        offset.y: 4
        color: Qt.rgba(0, 0, 0, 0.35)
        opacity: root.fused ? 0 : 1
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Theme.clusterRadius
        topLeftRadius: Theme.clusterRadius
        topRightRadius: Theme.clusterRadius
        bottomLeftRadius: root.joinBL ? 0 : Theme.clusterRadius
        bottomRightRadius: root.joinBR ? 0 : Theme.clusterRadius
        color: Theme.barBg
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        x: root.padding
        spacing: root.spacing
    }
}
