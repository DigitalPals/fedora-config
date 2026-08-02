import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland
import Quickshell.Widgets
import "Common"

PanelWindow {
    id: root

    visible: Notifs.toasts.length > 0
    screen: Screens.focused
    anchors { top: true; right: true }
    margins { top: Theme.barTopMargin + Theme.barHeight + 12; right: Theme.barSideMargin }
    implicitWidth: 380
    implicitHeight: Math.max(1, toastColumn.implicitHeight)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Column {
        id: toastColumn
        width: root.width
        spacing: 8

        Repeater {
            model: Notifs.toasts

            delegate: Rectangle {
                id: toast
                required property var modelData
                readonly property bool critical: modelData.urgency === NotificationUrgency.Critical
                property int remaining: Notifs.timeoutFor(modelData)
                readonly property bool hovered: hover.hovered

                width: toastColumn.width
                height: content.implicitHeight + 22
                radius: Theme.popRadius
                color: Theme.popBg
                border.width: 1
                border.color: critical ? Qt.rgba(232 / 255, 131 / 255, 122 / 255, 0.45) : Theme.popBorder

                HoverHandler { id: hover }

                Timer {
                    interval: 100
                    repeat: true
                    running: !toast.hovered
                    onTriggered: {
                        toast.remaining -= interval;
                        if (toast.remaining <= 0) {
                            stop();
                            Notifs.hideToast(toast.modelData, true);
                        }
                    }
                }

                Column {
                    id: content
                    x: 12
                    y: 11
                    width: parent.width - 24
                    spacing: 7

                    Row {
                        width: parent.width
                        spacing: 10

                        Item {
                            width: 22
                            height: 22

                            Image {
                                id: toastIcon
                                anchors.fill: parent
                                source: toast.modelData.appIcon ? Quickshell.iconPath(toast.modelData.appIcon, true) : ""
                                sourceSize: Qt.size(22, 22)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                visible: source !== ""
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !toastIcon.visible
                                text: toast.critical ? "\uf071" : "\uf0f3"
                                font.family: Theme.fontIcon
                                font.pixelSize: 14
                                color: toast.critical ? Theme.redText : Theme.accent
                            }
                        }

                        Column {
                            width: parent.width - 58
                            spacing: 2

                            Text {
                                width: parent.width
                                text: toast.modelData.summary || toast.modelData.appName || "Notification"
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                font.weight: 600
                                color: Theme.textHi
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: text !== ""
                                width: parent.width
                                text: (toast.modelData.body || "").replace(/<[^>]*>/g, "")
                                font.family: Theme.fontSans
                                font.pixelSize: 11
                                color: Theme.textLow
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            width: 20
                            height: 20
                            radius: 6
                            color: closeMouse.containsMouse ? Theme.hoverFillStrong : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "\uf00d"
                                font.family: Theme.fontIcon
                                font.pixelSize: 9
                                color: closeMouse.containsMouse ? Theme.textHi : Theme.textDim
                            }

                            MouseArea {
                                id: closeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: Notifs.dismiss(toast.modelData)
                            }
                        }
                    }

                    Row {
                        visible: toast.modelData.live && toast.modelData.actions.length > 0
                        spacing: 6

                        Repeater {
                            model: toast.modelData.actions.slice(0, 3)

                            delegate: Rectangle {
                                required property var modelData
                                height: 26
                                width: actionText.implicitWidth + 20
                                radius: Theme.chipRadius
                                color: actionMouse.containsMouse ? Theme.hoverFillStrong : Theme.cardFill

                                Text {
                                    id: actionText
                                    anchors.centerIn: parent
                                    text: modelData.text
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                    font.weight: 500
                                    color: actionMouse.containsMouse ? Theme.textHi : Theme.accent
                                }

                                MouseArea {
                                    id: actionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: Notifs.invoke(toast.modelData, modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
