import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland
import "Common"

// Readable fixed-width notification cards. Newest of at most three is on top;
// normal cards use an adaptive timer based on the configured duration, paused
// while hovered, and critical cards persist until explicitly dismissed.
// Corner, density, icons, body lines, and the timeout progress bar follow the
// Notifications settings page.
PanelWindow {
    id: root

    readonly property bool onTop: Settings.notifPosition.indexOf("top") === 0
    readonly property bool onLeft: Settings.notifPosition.indexOf("left") !== -1
    readonly property bool barSameEdge: Screens.hasBar(root.screen)
        && (Settings.position === "top") === onTop
    // Density scales the card's inner padding and content gap.
    readonly property int padV: Settings.notifDensity === "compact" ? 8
        : Settings.notifDensity === "roomy" ? 17 : 12
    readonly property int padH: Settings.notifDensity === "compact" ? 10
        : Settings.notifDensity === "roomy" ? 19 : 14

    visible: Notifs.toasts.length > 0
    screen: Screens.focused
    anchors {
        top: root.onTop
        bottom: !root.onTop
        left: root.onLeft
        right: !root.onLeft
    }
    margins.top: root.onTop
        ? (root.barSameEdge ? Theme.barTopMargin + Theme.barHeight : 8) : 0
    margins.bottom: !root.onTop
        ? (root.barSameEdge ? Theme.barTopMargin + Theme.barHeight : 8) : 0

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
        anchors.top: root.onTop ? parent.top : undefined
        anchors.topMargin: 12
        anchors.bottom: root.onTop ? undefined : parent.bottom
        anchors.bottomMargin: 12
        anchors.left: root.onLeft ? parent.left : undefined
        anchors.leftMargin: Theme.barSideMargin
        anchors.right: root.onLeft ? undefined : parent.right
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
            // ScriptModel diffs by entry identity, so removing one toast
            // reuses the surviving delegates instead of recreating them —
            // a plain array model would reset every card's countdown (and
            // hover state) whenever a sibling expired.
            model: ScriptModel {
                values: Notifs.toasts
            }

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
                    readonly property int total: Notifs.timeoutFor(slot.modelData)
                    readonly property bool showProgress: Settings.notifProgress && !critical
                    property int remaining: Notifs.timeoutFor(slot.modelData)

                    width: parent.width
                    height: cardContent.implicitHeight + root.padV * 2
                        + (showProgress ? 4 : 0)
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

                    // One continuous countdown instead of a 100ms tick: the
                    // progress bar moves at display rate and the card needs
                    // no repeating timer. Hovering stops the sequence with
                    // `remaining` frozen; unhovering restarts it from the
                    // frozen value with a freshly captured duration.
                    SequentialAnimation {
                        running: !card.hovered && !card.critical
                        ScriptAction {
                            script: countdown.duration = Math.max(1, card.remaining)
                        }
                        NumberAnimation {
                            id: countdown
                            target: card
                            property: "remaining"
                            to: 0
                        }
                        ScriptAction {
                            script: Notifs.hideToast(slot.modelData, true)
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
                        x: root.padH
                        y: root.padV
                        width: parent.width - root.padH * 2
                        spacing: 12

                        Item {
                            id: iconSlot
                            visible: Settings.notifIcons
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
                            width: cardContent.width - (iconSlot.visible
                                ? iconSlot.width + cardContent.spacing : 0)
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
                                visible: text !== "" && Settings.notifBodyLines > 0
                                width: parent.width
                                text: slot.modelData.displayBody || ""
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                color: card.critical ? Theme.textHi : Theme.icon
                                wrapMode: Text.Wrap
                                maximumLineCount: Math.max(1, Settings.notifBodyLines)
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

                    // Timeout progress (design 1c): a thin bar counting down
                    // the toast's remaining time. Freezes with the timer
                    // while hovered.
                    Rectangle {
                        visible: card.showProgress
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 1
                        height: 2
                        color: Qt.rgba(1, 1, 1, 0.07)

                        Rectangle {
                            height: parent.height
                            width: card.total > 0
                                ? parent.width * Math.max(0, Math.min(1, card.remaining / card.total))
                                : 0
                            color: Theme.accent
                        }
                    }
                }
            }
        }
    }
}
