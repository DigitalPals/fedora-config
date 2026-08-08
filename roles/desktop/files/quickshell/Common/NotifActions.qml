pragma ComponentBehavior: Bound
import QtQuick

// The contextual action pills under a notification's body. The first action
// carries the accent, the rest are neutral. They are revealed on hover, and
// `reveal` gates the lookup itself so a card that is not hovered never asks
// Notifs for its secondary actions.
Row {
    id: root

    required property var entry
    property bool reveal: false
    property string face: Theme.fontMenu
    property int pixelSize: Theme.fontCaption

    readonly property var items: reveal ? Notifs.secondaryActions(entry) : []

    visible: items.length > 0
    spacing: 6

    Repeater {
        model: root.items

        delegate: Rectangle {
            id: pill

            required property var modelData
            required property int index

            readonly property bool primary: index === 0

            height: 24
            width: Math.min(pillText.implicitWidth + 20, 160)
            radius: 7
            color: primary
                ? (pillMouse.containsMouse ? Theme.accentBg : Theme.accentBgSoft)
                : (pillMouse.containsMouse ? Theme.hoverFillStrong : Theme.hoverFill)

            Text {
                id: pillText
                anchors.centerIn: parent
                width: parent.width - 16
                text: pill.modelData.text
                font.family: root.face
                font.pixelSize: root.pixelSize
                font.weight: Theme.weightMedium
                color: pill.primary ? Theme.accent : Theme.textMid
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            MouseArea {
                id: pillMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Notifs.invoke(root.entry, pill.modelData)
            }
        }
    }
}
