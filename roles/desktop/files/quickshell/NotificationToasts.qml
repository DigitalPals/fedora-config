import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland
import "Common"

// Readable fixed-width notification cards. Newest of at most three is on top;
// normal cards use an adaptive 8–12 second timer, paused while hovered, and
// critical cards persist until explicitly dismissed.
PanelWindow {
    id: root

    visible: Notifs.toasts.length > 0
    screen: Screens.focused
    anchors {
        top: true
        right: true
    }
    margins.top: Settings.position === "top" ? Theme.barTopMargin + Theme.barHeight : 8

    readonly property int shadowPad: 36
    readonly property int cardWidth: 420
    implicitWidth: cardWidth + shadowPad + Theme.barSideMargin
    implicitHeight: toastColumn.implicitHeight + 12 + shadowPad
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        item: toastColumn
    }

    property real now: Date.now()

    Timer {
        interval: 30000
        repeat: true
        running: root.visible
        onTriggered: root.now = Date.now()
    }

    Column {
        id: toastColumn
        anchors.top: parent.top
        anchors.topMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: Theme.barSideMargin
        width: root.cardWidth
        spacing: 8

        add: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: 140
            }
        }

        Repeater {
            model: Notifs.toasts

            delegate: Item {
                id: slot
                required property var modelData

                width: toastColumn.width
                implicitHeight: card.height

                RectangularShadow {
                    anchors.fill: card
                    radius: card.radius
                    blur: 32
                    spread: 0
                    offset.y: 12
                    color: Qt.rgba(0, 0, 0, 0.5)
                }

                Rectangle {
                    id: card

                    readonly property bool critical: slot.modelData.urgency
                        === NotificationUrgency.Critical
                    readonly property bool hovered: cardHover.hovered
                    readonly property var actions: Notifs.secondaryActions(slot.modelData)
                    readonly property bool actionable: Notifs.canActivate(slot.modelData)
                    property int remaining: Notifs.timeoutFor(slot.modelData)

                    width: parent.width
                    height: cardContent.implicitHeight + 24
                    radius: 12
                    clip: true
                    color: critical ? Theme.redBgSoft
                        : hovered ? "#16171d" : Theme.popBg
                    border.width: 1
                    border.color: critical ? Theme.redBorder
                        : hovered ? Qt.rgba(1, 1, 1, 0.14) : Theme.popBorder

                    HoverHandler {
                        id: cardHover
                    }

                    Timer {
                        interval: 100
                        repeat: true
                        running: !card.hovered && !card.critical
                        onTriggered: {
                            card.remaining -= interval;
                            if (card.remaining <= 0) {
                                stop();
                                Notifs.hideToast(slot.modelData, true);
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: card.actionable
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Notifs.invokeDefault(slot.modelData)
                    }

                    Row {
                        id: cardContent
                        x: 14
                        y: 12
                        width: parent.width - 28
                        spacing: 12

                        Item {
                            id: iconSlot
                            width: 28
                            height: 28

                            Image {
                                id: appIcon
                                anchors.fill: parent
                                source: Notifs.iconSource(slot.modelData)
                                sourceSize: Qt.size(28, 28)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                visible: status === Image.Ready
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !appIcon.visible
                                text: card.critical ? ""
                                    : slot.modelData.webOrigin ? "" : ""
                                font.family: Theme.fontIcon
                                font.pixelSize: 18
                                color: card.critical ? Theme.redText : Theme.accent
                            }
                        }

                        Column {
                            id: copy
                            width: cardContent.width - iconSlot.width - cardContent.spacing
                            spacing: 5

                            Item {
                                width: parent.width
                                height: Math.max(headerText.implicitHeight, trailing.height)

                                Text {
                                    id: headerText
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - trailing.width - 8
                                    text: slot.modelData.displayAppName
                                        + (slot.modelData.displaySummary
                                            ? " · " + slot.modelData.displaySummary : "")
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: 600
                                    color: Theme.textHi
                                    elide: Text.ElideRight
                                }

                                Item {
                                    id: trailing
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 32
                                    height: 18

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !card.hovered
                                        text: Notifs.timeAgo(slot.modelData.arrived, root.now)
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                        font.weight: 500
                                        color: Theme.textDim
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: card.hovered
                                        text: "×"
                                        font.family: Theme.fontSans
                                        font.pixelSize: 17
                                        color: closeMouse.containsMouse ? Theme.textHi : Theme.textLow

                                        MouseArea {
                                            id: closeMouse
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Notifs.dismiss(slot.modelData)
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: text !== ""
                                width: parent.width
                                text: slot.modelData.displayBody || ""
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                color: card.critical ? Theme.textHi : Theme.icon
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                lineHeight: 1.15
                            }

                            Row {
                                id: actionsRow
                                visible: card.hovered && card.actions.length > 0
                                spacing: 6

                                Repeater {
                                    model: card.actions

                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index

                                        height: 24
                                        width: Math.min(actionText.implicitWidth + 20, 160)
                                        radius: 7
                                        color: index === 0
                                            ? (actionMouse.containsMouse
                                                ? Theme.accentAlpha(0.22)
                                                : Theme.accentBg)
                                            : (actionMouse.containsMouse
                                                ? Theme.hoverFillStrong : Qt.rgba(1, 1, 1, 0.07))
                                        readonly property color fg: index === 0
                                            ? Theme.accent : Theme.icon

                                        Text {
                                            id: actionText
                                            anchors.centerIn: parent
                                            width: parent.width - 16
                                            text: parent.modelData.text
                                            font.family: Theme.fontSans
                                            font.pixelSize: 11
                                            font.weight: 500
                                            color: parent.fg
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                        }

                                        MouseArea {
                                            id: actionMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Notifs.invoke(slot.modelData, parent.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
