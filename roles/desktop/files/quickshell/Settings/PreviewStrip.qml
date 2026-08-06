import QtQuick
import Quickshell.Widgets
import "../Common"

// Wallpaper-backed rounded strip with a bottom-right mono badge; pages put
// their miniature bar previews inside (design v2 preview strips).
ClippingRectangle {
    id: root

    property string badgeText: ""
    default property alias content: inner.data

    radius: 9
    color: Theme.barBg

    Image {
        anchors.fill: parent
        source: Wallpaper.current !== "" ? Wallpaper.url(Wallpaper.current) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: 1024
    }

    Item {
        id: inner
        anchors.fill: parent
    }

    Rectangle {
        visible: root.badgeText !== ""
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 5
        width: badgeLabel.implicitWidth + 12
        height: badgeLabel.implicitHeight + 4
        radius: 4
        color: Qt.rgba(0, 0, 0, 0.45)

        Text {
            id: badgeLabel
            anchors.centerIn: parent
            text: root.badgeText
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontCaption
            color: Theme.textMid
        }
    }
}
