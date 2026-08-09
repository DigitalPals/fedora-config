import QtQuick
import ".."
import "../../Common"

// GitHub repository feed, with the unread badge the Bell already draws.
BarModule {
    id: root

    moduleId: "gh"

    // The badge overlaps the icon through anchors, so the two stay siblings
    // inside an Item rather than becoming Row children — the Bell's shape,
    // because this is the Bell's badge.
    Item {
        id: ghModule

        width: ghIcon.width
        height: Theme.barHeight
        anchors.verticalCenter: parent.verticalCenter

        BarIcon {
            id: ghIcon
            // nf-fa-github: the mark the design draws, as a glyph rather than
            // an SVG so it takes the icon's idle/hover/held tint like every
            // other module. The toast ships assets/github.svg for the same
            // mark, because a notification icon cannot be a font glyph.
            glyph: "\uf09b"
            // A point over the shared size. The mark's ink is 89%\u00d787% of the
            // em where the coffee glyph beside it is 115%\u00d781% \u2014 same pixel
            // size, ~9% less apparent area \u2014 so at the token it reads as the
            // small one in the cluster. Measured from the font, not eyeballed.
            glyphSize: Theme.barIconSize + 1
            tooltip: {
                if (GitHub.error !== "")
                    return "GitHub · " + GitHub.error;
                const n = GitHub.unreadCount;
                if (n === 0)
                    return "GitHub";
                return "GitHub · " + n + (n === 1 ? " repo updated" : " repos updated");
            }
            tooltipAlign: 1
            host: root.host
            panelName: "github"
            isle: root.isle
            // The wrapper is the anchor: its height is the full bar row,
            // which is the rect the popout hangs under.
            anchorItem: ghModule
        }

        Rectangle {
            id: ghBadge
            readonly property bool showCount: GitHub.badgeMode === "count"
            visible: GitHub.badgeVisible
            anchors.top: ghIcon.top
            anchors.topMargin: showCount ? -3 : -1
            anchors.right: ghIcon.right
            anchors.rightMargin: showCount ? 0 : 3
            width: showCount ? Math.max(height, badgeCount.implicitWidth + 8) : 10
            height: showCount ? 15 : 10
            radius: height / 2
            // Count mode is a single accent pill ringed in bar color;
            // dot mode keeps the barBg ring + inner dot.
            color: showCount ? Theme.accent : Theme.barBg
            border.width: showCount ? 1 : 0
            border.color: Theme.barBg

            Rectangle {
                visible: !ghBadge.showCount
                anchors.centerIn: parent
                width: 6
                height: 6
                radius: 3
                color: Theme.accent
            }

            Text {
                id: badgeCount
                visible: ghBadge.showCount
                anchors.centerIn: parent
                text: GitHub.unreadCount > 99 ? "99+" : GitHub.unreadCount
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                font.weight: Theme.weightSemibold
                font.features: Theme.tabularNumberFeatures
                color: Theme.accentFg
            }
        }
    }
}
