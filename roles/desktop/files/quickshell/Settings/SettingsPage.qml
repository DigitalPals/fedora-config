import QtQuick
import "../Common"

Flickable {
    id: root
    default property alias content: contentRoot.data
    property int spacing: 10

    contentWidth: width
    contentHeight: contentRoot.childrenRect.height
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    clip: true
    flickDeceleration: 3000

    Item {
        id: contentRoot
        width: root.width
        height: childrenRect.height
    }

    Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: 2
        y: root.visibleArea.yPosition * (parent.height - height)
        width: 3
        height: Math.max(22, root.visibleArea.heightRatio * parent.height)
        radius: 2
        visible: root.contentHeight > root.height + 1
        color: Theme.accentAlpha(root.moving ? 0.8 : 0.35)
        Behavior on color { ColorAnimation { duration: Theme.popoutContentFadeDuration } }
    }
}
