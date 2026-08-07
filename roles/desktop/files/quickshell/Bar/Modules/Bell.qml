import QtQuick
import ".."
import "../../Common"

// Notification bell with its unread badge.
BarModule {
    id: root

    moduleId: "bell"

    // The badge overlaps the icon through anchors, so the two stay
    // siblings inside an Item rather than becoming Row children.
    Item {
        id: bellModule

        width: bellIcon.width
        height: Theme.barHeight
        anchors.verticalCenter: parent.verticalCenter

        BarIcon {
            id: bellIcon
            glyph: ""
            tooltip: Notifs.count + (Notifs.count === 1 ? " notification" : " notifications")
            tooltipAlign: 1
            host: root.host
            panelName: "notifications"
            isle: root.isle
            // The wrapper is the anchor: its height is the full bar row,
            // which is the rect the popout has always hung under.
            anchorItem: bellModule
        }

        Rectangle {
            id: bellBadge
            readonly property bool showCount: Settings.modOpts.bell.badge === "count"
            visible: Notifs.count > 0 && Settings.modOpts.bell.badge !== "off"
            anchors.top: bellIcon.top
            anchors.topMargin: showCount ? -3 : -1
            anchors.right: bellIcon.right
            anchors.rightMargin: showCount ? 0 : 3
            width: showCount ? Math.max(height, badgeCount.implicitWidth + 8) : 10
            height: showCount ? 15 : 10
            radius: height / 2
            // Count mode is a single accent pill ringed in bar color;
            // dot mode keeps the original barBg ring + inner dot.
            color: showCount
                ? (Notifs.hasUrgent ? Theme.red : Theme.accent) : Theme.barBg
            border.width: showCount ? 1 : 0
            border.color: Theme.barBg

            Rectangle {
                visible: !bellBadge.showCount
                anchors.centerIn: parent
                width: 6
                height: 6
                radius: 3
                color: Notifs.hasUrgent ? Theme.red : Theme.accent
            }

            Text {
                id: badgeCount
                visible: bellBadge.showCount
                anchors.centerIn: parent
                text: Notifs.count > 99 ? "99+" : Notifs.count
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                font.weight: Theme.weightSemibold
                font.features: Theme.tabularNumberFeatures
                color: Theme.accentFg
            }
        }
    }
}
