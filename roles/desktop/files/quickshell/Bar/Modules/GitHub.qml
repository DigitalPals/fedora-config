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

        readonly property color badgeTone: GitHub.badgeTone === "red" ? Theme.barRed
            : GitHub.badgeTone === "amber" ? Theme.barAmber : Theme.barAccent
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

        // The mark carries only the static running marker at its foot; pending
        // Inbox activity stays in the adjacent count instead of covering it.
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.barIconSize
            height: Theme.barIconSize

            BarBrandIcon {
                id: mark
                anchors.centerIn: parent
                width: Theme.barIconSize
                height: Theme.barIconSize
                name: "github"
                highlighted: ghChip.held || ghChip.hovered
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
                color: Theme.barAccent
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
            font.weight: Theme.weightMedium
            font.features: Theme.tabularNumberFeatures
            color: ghChip.badgeTone
        }
    }
}
