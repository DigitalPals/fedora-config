pragma ComponentBehavior: Bound
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

    // Toast type: an overlay surface, so it stays on the general UI face
    // rather than the menu font, and it is free of the popover scale's 12px
    // floor — the timestamp is deliberately small and monospaced.
    readonly property var cardStyle: ({
        face: Theme.fontSans,
        header: Theme.fontCaption,
        body: Theme.fontCaption,
        bodyColor: Theme.icon,
        bodyLines: Settings.notifBodyLines,
        bodyLeading: 1.15,
        stampFace: Theme.fontMono,
        stampSize: 10,
        stampCentred: true,
        trailingHeight: 18,
        close: 17,
        closeColor: Theme.textLow,
        pill: 11
    })

    visible: Notifs.toasts.length > 0
    screen: Screens.focused
    anchors {
        top: root.onTop
        bottom: !root.onTop
        left: root.onLeft
        right: !root.onLeft
    }
    // PanelWindow.margins is a Quickshell group qmllint cannot resolve.
    // qmllint disable unqualified
    margins.top: root.onTop
        ? (root.barSameEdge ? Theme.barTopMargin + Theme.barHeight : 8) : 0
    margins.bottom: !root.onTop
        ? (root.barSameEdge ? Theme.barTopMargin + Theme.barHeight : 8) : 0
    // qmllint enable unqualified

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

                readonly property bool critical: modelData.urgency
                    === NotificationUrgency.Critical
                readonly property int total: Notifs.timeoutFor(modelData)
                readonly property bool showProgress: Settings.notifProgress && !critical
                property int remaining: Notifs.timeoutFor(modelData)

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

                // One continuous countdown instead of a 100ms tick: the
                // progress bar moves at display rate and the card needs no
                // repeating timer. Hovering stops the sequence with
                // `remaining` frozen; unhovering restarts it from the frozen
                // value with a freshly captured duration.
                SequentialAnimation {
                    running: !card.hovered && !slot.critical
                    ScriptAction {
                        script: countdown.duration = Math.max(1, slot.remaining)
                    }
                    NumberAnimation {
                        id: countdown
                        target: slot
                        property: "remaining"
                        to: 0
                    }
                    ScriptAction {
                        script: Notifs.hideToast(slot.modelData, true)
                    }
                }

                NotifCard {
                    id: card

                    entry: slot.modelData
                    style: root.cardStyle
                    nowMs: root.now
                    padH: root.padH
                    padV: root.padV
                    showIcon: Settings.notifIcons

                    width: parent.width
                    height: contentHeight + (slot.showProgress ? 4 : 0)
                    radius: 12
                    clip: true
                    color: slot.critical ? Theme.redBgSoft
                        : hovered ? "#16171d" : Theme.popBg
                    border.width: 1
                    border.color: slot.critical ? Theme.redBorder
                        : hovered ? Qt.rgba(1, 1, 1, 0.14) : Theme.popBorder

                    onActivated: Notifs.invokeDefault(slot.modelData)
                    onCloseRequested: Notifs.dismiss(slot.modelData)

                    // Timeout progress (design 1c): a thin bar counting down
                    // the toast's remaining time. Freezes with the timer
                    // while hovered.
                    Rectangle {
                        visible: slot.showProgress
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 1
                        height: 2
                        color: Theme.activeFill

                        Rectangle {
                            height: parent.height
                            width: slot.total > 0
                                ? parent.width * Math.max(0, Math.min(1, slot.remaining / slot.total))
                                : 0
                            color: Theme.accent
                        }
                    }
                }
            }
        }
    }
}
