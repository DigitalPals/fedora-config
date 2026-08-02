import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Widgets
import "../Common"

Surface {
    id: root

    SystemClock {
        id: relativeClock
        precision: SystemClock.Seconds
    }

    // Header
    Item {
        width: parent.width
        height: 34

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Notifications"
            font.family: Theme.fontSans
            font.pixelSize: 12
            font.weight: 600
            color: Theme.textHi
        }

        Text {
            visible: Notifs.count > 0
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Clear all"
            font.family: Theme.fontSans
            font.pixelSize: 11
            font.weight: 500
            color: clearMouse.containsMouse ? "#c8e2f4" : Theme.accent

            MouseArea {
                id: clearMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: Notifs.clearAll()
            }
        }
    }

    Text {
        visible: Notifs.count === 0
        width: parent.width
        topPadding: 10
        bottomPadding: 14
        text: "No notifications"
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontSans
        font.pixelSize: 11
        color: Theme.textDim
    }

    Repeater {
        model: Notifs.entries.slice(0, 6)

        delegate: Rectangle {
            required property var modelData
            readonly property bool urgent: modelData.urgency === NotificationUrgency.Critical

            width: parent.width - 4
            x: 2
            height: rowContent.implicitHeight + 20
            radius: Theme.rowRadius
            color: urgent ? Theme.redBgSoft : rowMouse.containsMouse ? Theme.hoverFill : "transparent"

            Row {
                id: rowContent
                x: 10
                y: 10
                width: parent.width - 20
                spacing: 10

                Item {
                    width: 18
                    height: 18

                    Image {
                        id: appIconImg
                        anchors.fill: parent
                        source: modelData.appIcon ? Quickshell.iconPath(modelData.appIcon, true) : ""
                        sourceSize: Qt.size(18, 18)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        visible: source != ""
                    }

                    Text {
                        visible: !appIconImg.visible
                        anchors.centerIn: parent
                        text: urgent ? "\uf071" : "\uf05a"
                        font.family: Theme.fontIcon
                        font.pixelSize: 13
                        color: urgent ? Theme.redText : Theme.textMid
                    }
                }

                Column {
                    width: parent.width - 50
                    spacing: 2

                    Item {
                        width: parent.width
                        height: sumText.implicitHeight

                        Text {
                            id: sumText
                            width: parent.width - 30
                            text: modelData.summary
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: 500
                            color: Theme.textHi
                            elide: Text.ElideRight
                        }

                        Text {
                            anchors.right: parent.right
                            text: Notifs.timeAgo(modelData.arrived, relativeClock.date.getTime())
                            font.family: Theme.fontSans
                            font.pixelSize: 10
                            color: Theme.textDim
                        }
                    }

                    Text {
                        visible: text !== ""
                        width: parent.width
                        text: modelData.body.replace(/<[^>]*>/g, "")
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        color: Theme.textLow
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                    }
                }

                Text {
                    text: "\uf00d"
                    font.family: Theme.fontIcon
                    font.pixelSize: 9
                    color: closeMouse.containsMouse ? Theme.textHi : Theme.textDim

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        onClicked: Notifs.dismiss(modelData)
                    }
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                z: -1
            }
        }
    }

    HDivider {}

    // Do Not Disturb
    Item {
        width: parent.width
        height: 30

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Do Not Disturb"
            font.family: Theme.fontSans
            font.pixelSize: 11
            color: Theme.textDim
        }

        Toggle {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            checked: Notifs.dnd
            onToggled: v => Notifs.dnd = v
        }
    }
}
