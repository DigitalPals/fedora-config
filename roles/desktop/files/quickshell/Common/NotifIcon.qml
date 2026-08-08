import QtQuick

// A notification's source icon: the desktop entry's icon where one resolves,
// otherwise a glyph — a warning for critical, a globe for a web origin, a
// bell for everything else.
Item {
    id: root

    required property var entry
    property int iconSize: 28
    property bool urgent: false

    Image {
        id: image
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        source: Notifs.iconSource(root.entry)
        sourceSize: Qt.size(root.iconSize, root.iconSize)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        visible: status === Image.Ready
    }

    Text {
        anchors.centerIn: parent
        visible: !image.visible
        text: root.urgent ? "" : root.entry.webOrigin ? "" : ""
        font.family: Theme.fontIcon
        font.pixelSize: Math.max(Theme.fontCaption, root.iconSize - 8)
        color: root.urgent ? Theme.redText : Theme.accent
    }
}
