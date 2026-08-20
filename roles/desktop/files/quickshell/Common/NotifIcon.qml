import QtQuick

// A notification's source icon: the desktop entry's icon where one resolves,
// otherwise a glyph — a warning for critical, a globe for a web origin, a
// bell for everything else. Toasts opt into a compact tinted well so icons
// with very different silhouettes keep the same visual weight.
Item {
    id: root

    required property var entry
    property int iconSize: 28
    property bool urgent: false
    property bool framed: false

    Rectangle {
        anchors.fill: parent
        radius: Math.min(width, height) * 0.32
        color: root.framed
            ? (root.urgent ? Theme.redBgSoft : Theme.accentBgSoft)
            : "transparent"
        border.width: root.framed ? 1 : 0
        border.color: root.urgent ? Theme.redBorder : Theme.hairlineSoft

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

        Sym {
            anchors.centerIn: parent
            visible: !image.visible
            name: root.urgent ? "warning" : root.entry.webOrigin ? "public" : "notifications"
            size: Math.max(Theme.fontCaption, root.iconSize - (root.framed ? 3 : 8))
            fill: root.framed ? 1 : 0
            color: root.urgent ? Theme.redText : Theme.accent
        }
    }
}
