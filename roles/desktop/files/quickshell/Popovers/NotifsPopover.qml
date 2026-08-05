import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Widgets
import "../Common"

// Notification center (design t4, 4d + 4e merged): entries group per app.
// A collapsed group reads as a 4e stack — newest entry previewed, +N
// badge, depth peek behind — and clicking it expands to 4d flat rows
// under a group header with a group-clear ×. The header carries the
// count badge and clear-all; groups whose newest entry is over an hour
// old sit dimmed under an EARLIER separator; DND is a proper toggle row
// in the footer.
Surface {
    id: root

    SystemClock {
        id: relativeClock
        precision: SystemClock.Seconds
    }

    // Groups expanded to their row list this open; keyed by app name.
    property var expandedApps: ({})

    function toggleApp(app) {
        const next = Object.assign({}, expandedApps);
        next[app] = !next[app];
        expandedApps = next;
    }

    function clearGroup(group) {
        for (const entry of group.items)
            Notifs.dismiss(entry);
    }

    readonly property var groups: {
        const seen = {};
        const list = [];
        for (const entry of Notifs.entries.slice(0, 18)) {
            const key = entry.appName || "Other";
            let group = seen[key];
            if (!group) {
                group = { app: key, items: [] };
                seen[key] = group;
                list.push(group);
            }
            group.items.push(entry);
        }
        return list;
    }

    readonly property real nowMs: relativeClock.date.getTime()
    readonly property var recentGroups: groups.filter(g => nowMs - g.items[0].arrived < 3600000)
    readonly property var earlierGroups: groups.filter(g => nowMs - g.items[0].arrived >= 3600000)

    // ---- shared bits -----------------------------------------------------

    component AppIcon: Item {
        id: iconSlot
        required property var entry
        property int iconSize: 15
        property bool urgent: false

        Image {
            id: iconImg
            anchors.centerIn: parent
            width: iconSlot.iconSize
            height: iconSlot.iconSize
            source: Notifs.iconSource(iconSlot.entry)
            sourceSize: Qt.size(iconSlot.iconSize, iconSlot.iconSize)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            visible: status === Image.Ready
        }

        Text {
            visible: !iconImg.visible
            anchors.centerIn: parent
            text: iconSlot.urgent ? "" : ""
            font.family: Theme.fontIcon
            font.pixelSize: Math.max(Theme.fontCaption, iconSlot.iconSize - 2)
            color: iconSlot.urgent ? Theme.redText : Theme.textMid
        }
    }

    component NotifRow: Rectangle {
        id: row
        required property var entry
        readonly property bool urgent: entry.urgency === NotificationUrgency.Critical
        readonly property string bodyText: (entry.body || "").replace(/<[^>]*>/g, "")

        width: parent.width - 4
        x: 2
        height: rowCol.implicitHeight + 12
        radius: Theme.rowRadius
        color: urgent ? Theme.redBgSoft : rowMouse.containsMouse ? Theme.hoverFill : "transparent"

        Column {
            id: rowCol
            // Indented under the group header's icon chip (4d).
            x: 33
            y: 6
            width: parent.width - 43
            spacing: 2

            Item {
                width: parent.width
                height: sumText.implicitHeight

                Text {
                    id: sumText
                    width: parent.width - 52
                    text: row.entry.summary || row.bodyText
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontBody
                    font.weight: Theme.weightMedium
                    color: Theme.textHi
                    elide: Text.ElideRight
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    text: Notifs.timeAgo(row.entry.arrived, root.nowMs)
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontCaption
                    font.weight: Theme.weightMedium
                    color: Theme.textDim
                }

                Text {
                    visible: rowMouse.containsMouse || rowCloseMouse.containsMouse
                    anchors.right: parent.right
                    text: ""
                    font.family: Theme.fontIcon
                    font.pixelSize: Theme.fontCaption
                    color: rowCloseMouse.containsMouse ? Theme.textHi : Theme.textDim

                    MouseArea {
                        id: rowCloseMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        onClicked: Notifs.dismiss(row.entry)
                    }
                }
            }

            Text {
                visible: text !== "" && text !== sumText.text
                width: parent.width
                text: row.bodyText
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontSecondary
                color: Theme.textLow
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                lineHeight: Theme.proseLineHeight
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            z: -1
        }
    }

    component GroupBlock: Column {
        id: block
        required property var group
        property bool dim: false
        readonly property bool expanded: root.expandedApps[group.app] === true
        readonly property var newest: group.items[0]
        readonly property bool hasUrgent: group.items.some(i => i.urgency === NotificationUrgency.Critical)

        width: parent.width
        opacity: dim ? 0.65 : 1

        // ---- collapsed: 4e stack card ------------------------------------
        Item {
            visible: !block.expanded
            width: parent.width - 4
            x: 2
            height: stackCard.height + (block.group.items.length > 2 ? 8 : block.group.items.length > 1 ? 4 : 0)

            Rectangle {
                visible: block.group.items.length > 2
                anchors.bottom: parent.bottom
                x: 14
                width: parent.width - 28
                height: 12
                radius: 10
                color: Theme.cardFill
                opacity: 0.5
            }

            Rectangle {
                visible: block.group.items.length > 1
                anchors.bottom: parent.bottom
                anchors.bottomMargin: block.group.items.length > 2 ? 4 : 0
                x: 7
                width: parent.width - 14
                height: 12
                radius: 11
                color: Theme.cardFill
                opacity: 0.75
            }

            Rectangle {
                id: stackCard
                width: parent.width
                height: cardRow.implicitHeight + 20
                radius: 11
                color: cardMouse.containsMouse ? Theme.hoverFill : Theme.cardFill
                border.width: 1
                border.color: block.hasUrgent ? Theme.redBorder : Theme.hairlineSoft

                Row {
                    id: cardRow
                    x: 12
                    y: 10
                    width: parent.width - 24
                    spacing: 10

                    Rectangle {
                        width: 28
                        height: 28
                        radius: 8
                        color: Qt.rgba(1, 1, 1, 0.06)

                        AppIcon {
                            anchors.fill: parent
                            entry: block.newest
                            iconSize: 15
                            urgent: block.hasUrgent
                        }
                    }

                    Column {
                        width: parent.width - 38
                        spacing: 2

                        Item {
                            width: parent.width
                            height: appText.implicitHeight

                            Row {
                                id: leftBits
                                spacing: 6

                                Text {
                                    id: appText
                                    width: Math.min(implicitWidth, cardRow.width - 38 - rightBits.width - 60)
                                    text: block.group.app
                                    font.family: Theme.fontMenu
                                    font.pixelSize: Theme.fontBody
                                    font.weight: Theme.weightSemibold
                                    color: Theme.textHi
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    visible: block.group.items.length > 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: plusText.implicitWidth + 12
                                    height: plusText.implicitHeight + 4
                                    radius: 6
                                    color: Theme.accentBg

                                    Text {
                                        id: plusText
                                        anchors.centerIn: parent
                                        text: "+" + (block.group.items.length - 1)
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontCaption
                                        font.weight: Theme.weightSemibold
                                        color: Theme.accent
                                    }
                                }
                            }

                            Row {
                                id: rightBits
                                anchors.right: parent.right
                                spacing: 8

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Notifs.timeAgo(block.newest.arrived, root.nowMs)
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontCaption
                                    font.weight: Theme.weightMedium
                                    color: Theme.textDim
                                }

                                Text {
                                    visible: cardMouse.containsMouse || cardCloseMouse.containsMouse
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: ""
                                    font.family: Theme.fontIcon
                                    font.pixelSize: Theme.fontCaption
                                    color: cardCloseMouse.containsMouse ? Theme.textHi : Theme.textDim

                                    MouseArea {
                                        id: cardCloseMouse
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        hoverEnabled: true
                                        onClicked: root.clearGroup(block.group)
                                    }
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            text: block.newest.summary || (block.newest.body || "").replace(/<[^>]*>/g, "")
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontSecondary
                            color: Theme.icon
                            elide: Text.ElideRight
                        }
                    }
                }

                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    z: -1
                    onClicked: root.toggleApp(block.group.app)
                }
            }
        }

        // ---- expanded: 4d group header + flat rows -----------------------
        Column {
            visible: block.expanded
            width: parent.width

            Item {
                width: parent.width - 4
                x: 2
                height: Theme.controlHeight

                Row {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7

                    Rectangle {
                        width: 18
                        height: 18
                        radius: 5
                        color: Qt.rgba(1, 1, 1, 0.06)

                        AppIcon {
                            anchors.fill: parent
                            entry: block.newest
                            iconSize: 11
                            urgent: block.hasUrgent
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: block.group.app
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontSecondary
                        font.weight: Theme.weightSemibold
                        color: Theme.icon
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: block.group.items.length
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontCaption
                        font.weight: Theme.weightMedium
                        color: Theme.textFaint
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    font.family: Theme.fontIcon
                    font.pixelSize: Theme.fontCaption
                    color: groupCloseMouse.containsMouse ? Theme.textHi : Theme.textDim

                    MouseArea {
                        id: groupCloseMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        onClicked: root.clearGroup(block.group)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.rightMargin: 26
                    onClicked: root.toggleApp(block.group.app)
                }
            }

            Repeater {
                model: block.group.items

                delegate: NotifRow {
                    required property var modelData
                    entry: modelData
                }
            }
        }
    }

    // ---- header ----------------------------------------------------------

    Item {
        width: parent.width
        height: Theme.rowHeight

        Row {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Notifications"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontBody
                font.weight: Theme.weightSemibold
                color: Theme.textHi
            }

            Rectangle {
                visible: Notifs.count > 0
                anchors.verticalCenter: parent.verticalCenter
                width: countText.implicitWidth + 12
                height: countText.implicitHeight + 4
                radius: 6
                color: Theme.accentBg

                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: Notifs.count
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontCaption
                    font.weight: Theme.weightSemibold
                    color: Theme.accent
                }
            }
        }

        Text {
            visible: Notifs.count > 0
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Clear all"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontSecondary
            font.weight: Theme.weightMedium
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
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontSecondary
        color: Theme.textDim
    }

    // ---- groups ----------------------------------------------------------

    Column {
        width: parent.width
        spacing: 6

        Repeater {
            model: root.recentGroups

            delegate: GroupBlock {
                required property var modelData
                group: modelData
            }
        }

        Item {
            visible: root.earlierGroups.length > 0
            width: parent.width
            height: Theme.controlHeight

            Text {
                id: earlierLabel
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "EARLIER"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                font.weight: Theme.weightSemibold
                font.letterSpacing: 1.2
                color: Theme.textFaint
            }

            Rectangle {
                anchors.left: earlierLabel.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Theme.hairlineSoft
            }
        }

        Repeater {
            model: root.earlierGroups

            delegate: GroupBlock {
                required property var modelData
                group: modelData
                dim: true
            }
        }
    }

    HDivider {}

    // ---- footer: Do Not Disturb -----------------------------------------

    Item {
        width: parent.width
        height: Theme.controlHeight

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Do Not Disturb"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontSecondary
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
