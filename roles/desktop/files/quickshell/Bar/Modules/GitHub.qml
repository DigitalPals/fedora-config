import QtQuick
import ".."
import "../../Common"
import "../../Common/GitHubHelpers.js" as Helpers

// GitHub Inbox and repository feed, inside the right cluster's chip group.
// Running state is independent from the configurable unread badge, so
// badge-off still shows live workflows.
BarModule {
    id: root

    moduleId: "gh"
    detailSaving: ghChip.detailSaving

    BarChip {
        id: ghChip

        readonly property color badgeTone: GitHub.badgeTone === "red" ? Theme.red
            : GitHub.badgeTone === "amber" ? Theme.amber : Theme.accent
        readonly property real detailSaving: countLabel.visible
            ? countLabel.implicitWidth + spacing : 0

        host: root.host
        panelName: "github"
        isle: root.isle
        anchorItem: root.groupAnchor ?? ghChip
        shape: "inner"
        hPadding: 9
        spacing: 6
        tooltipAlign: 1
        tooltip: {
            let summary = Helpers.githubTooltip(GitHub.runningCount,
                GitHub.pendingInboxCount, GitHub.unreadRepoCount);
            if (GitHub.error !== "")
                summary += " · repositories unavailable";
            if (GitHub.inboxError !== "")
                summary += " · Inbox paused";
            return summary;
        }

        // The mark, with its two markers hung off it: a static running dot at
        // the foot, and the unread badge at the shoulder.
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: mark.implicitWidth
            height: mark.implicitHeight

            Text {
                id: mark
                anchors.centerIn: parent
                // nf-fa-github: the mark the design draws. Kept as a Nerd Font
                // glyph rather than a Material Symbol because Material Symbols
                // carries no brand marks, and the shell already ships the face.
                text: ""
                font.family: Theme.fontNerd
                font.pixelSize: Theme.barIconSize
                color: ghChip.held || ghChip.hovered ? Theme.textHi : Theme.icon

                Behavior on color {
                    ColorAnimation { duration: Theme.chipFadeDuration }
                }
            }

            // Running status: a static marker, deliberately not tied to badge
            // visibility and carrying no pulse.
            Rectangle {
                visible: GitHub.runningCount > 0
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1
                width: 5
                height: 5
                radius: 2.5
                color: Theme.accent
            }

            Rectangle {
                id: badge

                readonly property bool showCount: GitHub.badgeMode === "count"

                visible: GitHub.badgeVisible
                anchors.top: parent.top
                anchors.topMargin: showCount ? -3 : -1
                anchors.right: parent.right
                anchors.rightMargin: showCount ? -2 : 0
                width: showCount ? Math.max(height, badgeCount.implicitWidth + 8) : 8
                height: showCount ? 14 : 8
                radius: height / 2
                color: showCount ? ghChip.badgeTone : ghChip.badgeTone

                Text {
                    id: badgeCount
                    visible: badge.showCount
                    anchors.centerIn: parent
                    text: GitHub.pendingInboxCount > 99 ? "99+" : GitHub.pendingInboxCount
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontMicro
                    font.weight: Theme.weightHeavy
                    font.features: Theme.tabularNumberFeatures
                    color: Theme.textOnAccent
                }
            }
        }

        Text {
            id: countLabel
            visible: !root.compact && GitHub.pendingInboxCount > 0
                && GitHub.badgeMode !== "count"
            anchors.verticalCenter: parent.verticalCenter
            text: GitHub.pendingInboxCount
            font.family: Theme.fontMenu
            font.pixelSize: Theme.barLabelSize
            font.weight: Theme.weightHeavy
            font.features: Theme.tabularNumberFeatures
            color: ghChip.badgeTone
        }
    }
}
