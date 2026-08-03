import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland
import "Common"

// Notification popups (design t4, treatment 4b): the quietest possible —
// each toast is a single 38px one-liner row, app · body · time, sized to
// its content and right-aligned under the bar. Actions and the close ×
// only appear on hover, which also pauses the countdown. Critical
// urgency expands to two lines, goes red-border (same treatment as mute)
// and persists until dismissed. Newest of max 3 stacks on top.
PanelWindow {
    id: root

    visible: Notifs.toasts.length > 0
    screen: Screens.focused
    anchors {
        top: true
        right: true
    }
    margins {
        top: Theme.barTopMargin + Theme.barHeight
    }
    // Widest card plus breathing room for the drop shadows; the right
    // side only gets the bar margin, which softly clips the blur there.
    readonly property int shadowPad: 36
    readonly property int maxCard: 420
    implicitWidth: maxCard + shadowPad + Theme.barSideMargin
    implicitHeight: toastColumn.implicitHeight + 12 + shadowPad
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Pointer input only over the stack; the shadow gutter falls through.
    mask: Region {
        item: toastColumn
    }

    // Coarse clock for the relative timestamps; only critical toasts
    // live long enough to age past "now".
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
        width: root.maxCard
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

                    readonly property bool critical: slot.modelData.urgency === NotificationUrgency.Critical
                    readonly property bool hovered: hover.hovered
                    readonly property string bodyText: (slot.modelData.body || "").replace(/<[^>]*>/g, "")
                    readonly property var actions: slot.modelData.live ? slot.modelData.actions.slice(0, 2) : []
                    property int remaining: Notifs.timeoutFor(slot.modelData)

                    anchors.right: parent.right
                    width: Math.min(inner.implicitWidth + 28, toastColumn.width)
                    height: critical ? inner.implicitHeight + 18 : 38
                    radius: 11
                    clip: true
                    color: hovered && !critical ? "#16171d" : Theme.popBg
                    border.width: 1
                    border.color: critical ? Theme.redBorder
                        : hovered ? Qt.rgba(1, 1, 1, 0.14) : Theme.popBorder

                    Behavior on width {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }
                    }

                    HoverHandler {
                        id: hover
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

                    Row {
                        id: inner
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 15
                            height: 15

                            Image {
                                id: appIcon
                                anchors.fill: parent
                                source: Notifs.iconSource(slot.modelData)
                                sourceSize: Qt.size(15, 15)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                // source is a url, so a strict compare against
                                // "" never matches; readiness also covers icon
                                // names that fail to resolve.
                                visible: status === Image.Ready
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !appIcon.visible
                                text: card.critical ? "" : ""
                                font.family: Theme.fontIcon
                                font.pixelSize: 12
                                color: card.critical ? Theme.redText : Theme.accent
                            }
                        }

                        // ---- one-liner: app · body · time -----------------
                        Text {
                            id: nameText
                            visible: !card.critical
                            anchors.verticalCenter: parent.verticalCenter
                            text: slot.modelData.appName || "Notification"
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: 600
                            color: Theme.textHi
                        }

                        Text {
                            id: lineText
                            visible: !card.critical
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property real chrome: 28 + 15 + nameText.implicitWidth
                                + timeText.implicitWidth + inner.spacing * 3
                                + (card.hovered ? actionsRow.implicitWidth + closeText.implicitWidth + inner.spacing * (card.actions.length > 0 ? 2 : 1) : 0)
                            width: Math.max(40, Math.min(implicitWidth, toastColumn.width - chrome))
                            text: slot.modelData.summary || card.bodyText
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            color: Theme.icon
                            elide: Text.ElideRight
                        }

                        Text {
                            id: timeText
                            visible: !card.critical
                            anchors.verticalCenter: parent.verticalCenter
                            text: Notifs.timeAgo(slot.modelData.arrived, root.now)
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            font.weight: 500
                            color: Theme.textDim
                        }

                        // ---- critical: two lines, persists ----------------
                        Column {
                            visible: card.critical
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                width: Math.min(implicitWidth, 300)
                                text: slot.modelData.summary || slot.modelData.appName || "Notification"
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                font.weight: 600
                                color: Theme.textHi
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: text !== ""
                                width: Math.min(implicitWidth, 300)
                                text: card.bodyText
                                font.family: Theme.fontSans
                                font.pixelSize: 11
                                color: Theme.icon
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            visible: card.critical
                            anchors.verticalCenter: parent.verticalCenter
                            text: "CRITICAL"
                            font.family: Theme.fontMono
                            font.pixelSize: 9
                            font.weight: 600
                            font.letterSpacing: 0.8
                            color: Theme.redText
                        }

                        // ---- hover extras: action pills + close -----------
                        Row {
                            id: actionsRow
                            visible: card.hovered && card.actions.length > 0
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Repeater {
                                model: card.actions

                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index

                                    height: 22
                                    width: actionText.implicitWidth + 20
                                    radius: 7
                                    color: index === 0
                                        ? (actionMouse.containsMouse ? Qt.rgba(158 / 255, 203 / 255, 235 / 255, 0.22) : Theme.accentBg)
                                        : (actionMouse.containsMouse ? Theme.hoverFillStrong : Qt.rgba(1, 1, 1, 0.07))
                                    readonly property color fg: index === 0 ? Theme.accent : Theme.icon

                                    Text {
                                        id: actionText
                                        anchors.centerIn: parent
                                        text: parent.modelData.text
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        font.weight: 500
                                        color: parent.fg
                                    }

                                    MouseArea {
                                        id: actionMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: Notifs.invoke(slot.modelData, parent.modelData)
                                    }
                                }
                            }
                        }

                        Text {
                            id: closeText
                            visible: card.hovered
                            anchors.verticalCenter: parent.verticalCenter
                            text: "×"
                            font.family: Theme.fontSans
                            font.pixelSize: 13
                            color: closeMouse.containsMouse ? Theme.textHi : Theme.textLow

                            MouseArea {
                                id: closeMouse
                                anchors.fill: parent
                                anchors.margins: -5
                                hoverEnabled: true
                                onClicked: Notifs.dismiss(slot.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
