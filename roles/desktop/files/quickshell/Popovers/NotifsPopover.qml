pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../Common"

// Notification center built from the same anatomy as the popup card: source
// icon, app · summary header, timestamp, wrapped body, whole-card default
// activation, contextual actions, and hover-to-dismiss. Repeated sources are
// collapsed under one card and expand into a source-headed list.
Surface {
    id: root

    implicitWidth: Theme.popWideWidth
    spacing: 10

    SystemClock {
        id: relativeClock
        precision: SystemClock.Seconds
    }

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
            const key = entry.displayAppName || "Other";
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
    readonly property var recentGroups: groups.filter(group =>
        nowMs - group.items[0].arrived < 3600000)
    readonly property var earlierGroups: groups.filter(group =>
        nowMs - group.items[0].arrived >= 3600000)

    // ---- shared card pieces ---------------------------------------------

    component AppIcon: Item {
        id: iconSlot
        required property var entry
        property int iconSize: 28
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
            text: iconSlot.urgent ? "" : iconSlot.entry.webOrigin ? "" : ""
            font.family: Theme.fontIcon
            font.pixelSize: Math.max(Theme.fontCaption, iconSlot.iconSize - 8)
            color: iconSlot.urgent ? Theme.redText : Theme.accent
        }
    }

    component ActionPills: Row {
        id: pills
        required property var entry
        property bool reveal: false
        readonly property var items: reveal ? Notifs.secondaryActions(entry) : []

        visible: items.length > 0
        spacing: 6

        Repeater {
            model: pills.items

            delegate: Rectangle {
                required property var modelData
                required property int index

                height: 24
                width: Math.min(actionText.implicitWidth + 20, 146)
                radius: 7
                color: index === 0
                    ? (actionMouse.containsMouse ? Theme.accentBg : Theme.accentBgSoft)
                    : (actionMouse.containsMouse ? Theme.hoverFillStrong
                        : Qt.rgba(1, 1, 1, 0.05))
                readonly property color foreground: index === 0
                    ? Theme.accent : Theme.textMid

                Text {
                    id: actionText
                    anchors.centerIn: parent
                    width: parent.width - 16
                    text: parent.modelData.text
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    font.weight: Theme.weightMedium
                    color: parent.foreground
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: actionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifs.invoke(pills.entry, parent.modelData)
                }
            }
        }
    }

    component NotifCard: Rectangle {
        id: card
        required property var entry
        property int groupCount: 1
        property bool showApp: true
        property bool nested: false
        property bool groupUrgent: false
        signal activated
        signal closeRequested

        readonly property bool urgent: groupUrgent
            || entry.urgency === NotificationUrgency.Critical
        readonly property bool hovered: cardHover.hovered
        readonly property bool actionable: groupCount > 1 || Notifs.canActivate(entry)

        height: cardContent.implicitHeight + (nested ? 16 : 24)
        radius: nested ? Theme.rowRadius : 11
        color: urgent ? Theme.redBgSoft
            : hovered ? Theme.hoverFill : nested ? "transparent" : Theme.cardFill
        border.width: nested ? 0 : 1
        border.color: urgent ? Theme.redBorder : Theme.hairlineSoft

        Rectangle {
            visible: card.nested
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 10
            height: 1
            color: Theme.hairlineSoft
        }

        HoverHandler {
            id: cardHover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: card.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (card.actionable)
                    card.activated();
            }
        }

        Row {
            id: cardContent
            x: card.nested ? 10 : 12
            y: card.nested ? 8 : 12
            width: parent.width - x * 2
            spacing: card.showApp ? 12 : 0

            AppIcon {
                visible: card.showApp
                width: 28
                height: 28
                entry: card.entry
                urgent: card.urgent
            }

            Column {
                width: cardContent.width - (card.showApp ? 40 : 0)
                spacing: 5

                Item {
                    width: parent.width
                    height: Math.max(cardHeader.implicitHeight, cardTrailing.height)

                    Text {
                        id: cardHeader
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - cardTrailing.width - 8
                        text: card.showApp
                            ? card.entry.displayAppName
                                + (card.entry.displaySummary
                                    ? " · " + card.entry.displaySummary : "")
                            : (card.entry.displaySummary || card.entry.displayAppName)
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontSecondary
                        font.weight: Theme.weightSemibold
                        color: Theme.textHi
                        elide: Text.ElideRight
                    }

                    Item {
                        id: cardTrailing
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: card.groupCount > 1 ? 60 : 32
                        height: 20

                        Rectangle {
                            visible: card.groupCount > 1
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: groupCountText.implicitWidth + 12
                            height: 20
                            radius: 6
                            color: Theme.accentBg

                            Text {
                                id: groupCountText
                                anchors.centerIn: parent
                                text: card.groupCount
                                font.family: Theme.fontMenu
                                font.pixelSize: Theme.fontCaption
                                font.weight: Theme.weightSemibold
                                font.features: Theme.tabularNumberFeatures
                                color: Theme.accent
                            }
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !card.hovered
                            text: Notifs.timeAgo(card.entry.arrived, root.nowMs)
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontCaption
                            font.weight: Theme.weightMedium
                            font.features: Theme.tabularNumberFeatures
                            color: Theme.textDim
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: card.hovered
                            text: "×"
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontHeading
                            color: closeMouse.containsMouse ? Theme.textHi : Theme.textDim

                            MouseArea {
                                id: closeMouse
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: card.closeRequested()
                            }
                        }
                    }
                }

                Text {
                    visible: text !== ""
                    width: parent.width
                    text: card.entry.displayBody || ""
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontSecondary
                    color: card.urgent ? Theme.textHi : Theme.textLow
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    lineHeight: 1.25
                }

                ActionPills {
                    entry: card.entry
                    reveal: card.hovered && card.groupCount === 1
                }
            }
        }
    }

    component GroupBlock: Column {
        id: block
        required property var group
        property bool dim: false
        readonly property bool expanded: root.expandedApps[group.app] === true
        readonly property var newest: group.items[0]
        readonly property bool hasUrgent: group.items.some(item =>
            item.urgency === NotificationUrgency.Critical)

        width: parent.width
        opacity: dim ? 0.7 : 1

        NotifCard {
            visible: !block.expanded
            width: parent.width
            entry: block.newest
            groupCount: block.group.items.length
            groupUrgent: block.hasUrgent
            onActivated: {
                if (block.group.items.length > 1)
                    root.toggleApp(block.group.app);
                else
                    Notifs.invokeDefault(block.newest);
            }
            onCloseRequested: root.clearGroup(block.group)
        }

        Rectangle {
            visible: block.expanded
            width: parent.width
            height: expandedColumn.implicitHeight + 2
            radius: 11
            color: Theme.cardFill
            border.width: 1
            border.color: block.hasUrgent ? Theme.redBorder : Theme.hairlineSoft
            clip: true

            Column {
                id: expandedColumn
                x: 1
                y: 1
                width: parent.width - 2

                Item {
                    id: groupHeader
                    width: parent.width
                    height: 44

                    HoverHandler {
                        id: groupHeaderHover
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.rightMargin: 34
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleApp(block.group.app)
                    }

                    AppIcon {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24
                        iconSize: 24
                        entry: block.newest
                        urgent: block.hasUrgent
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 44
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 110
                        text: block.group.app
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontSecondary
                        font.weight: Theme.weightSemibold
                        color: Theme.textHi
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 42
                        anchors.verticalCenter: parent.verticalCenter
                        width: expandedCount.implicitWidth + 12
                        height: 20
                        radius: 6
                        color: Theme.accentBg

                        Text {
                            id: expandedCount
                            anchors.centerIn: parent
                            text: block.group.items.length
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontCaption
                            font.weight: Theme.weightSemibold
                            font.features: Theme.tabularNumberFeatures
                            color: Theme.accent
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 13
                        anchors.verticalCenter: parent.verticalCenter
                        text: groupHeaderHover.hovered ? "×" : "⌃"
                        font.family: Theme.fontMenu
                        font.pixelSize: groupHeaderHover.hovered
                            ? Theme.fontHeading : Theme.fontBody
                        color: groupCloseMouse.containsMouse ? Theme.textHi : Theme.textDim

                        MouseArea {
                            id: groupCloseMouse
                            anchors.fill: parent
                            anchors.margins: -6
                            enabled: groupHeaderHover.hovered
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.clearGroup(block.group)
                        }
                    }
                }

                Repeater {
                    model: block.group.items

                    delegate: NotifCard {
                        required property var modelData
                        width: expandedColumn.width
                        entry: modelData
                        nested: true
                        showApp: false
                        onActivated: Notifs.invokeDefault(entry)
                        onCloseRequested: Notifs.dismiss(entry)
                    }
                }
            }
        }
    }

    // ---- header ---------------------------------------------------------

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
                font.pixelSize: Theme.fontHeading
                font.weight: Theme.weightSemibold
                color: Theme.textHi
            }

            Rectangle {
                visible: Notifs.count > 0
                anchors.verticalCenter: parent.verticalCenter
                width: countText.implicitWidth + 12
                height: 22
                radius: 7
                color: Theme.accentBg

                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: Notifs.count
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    font.weight: Theme.weightSemibold
                    font.features: Theme.tabularNumberFeatures
                    color: Theme.accent
                }
            }
        }

        LinkText {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Clear all"
            onClicked: Notifs.clearAll()
        }
    }

    Item {
        visible: Notifs.count === 0
        width: parent.width
        height: 70

        Column {
            anchors.centerIn: parent
            spacing: 6

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: ""
                font.family: Theme.fontIcon
                font.pixelSize: Theme.iconLarge
                color: Theme.textFaint
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No notifications"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontSecondary
                color: Theme.textDim
            }
        }
    }

    // ---- grouped history ------------------------------------------------

    Column {
        width: parent.width
        spacing: 8

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

    // ---- footer ---------------------------------------------------------

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
            onToggled: value => Notifs.setDnd(value)
        }
    }
}
