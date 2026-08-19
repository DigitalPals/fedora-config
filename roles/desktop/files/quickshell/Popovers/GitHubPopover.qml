pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/GitHubHelpers.js" as Helpers

// Inbox opens first. Repositories is the existing browser, and Commits is
// its drill-down. Nothing here mutates GitHub: opening a row only launches its
// browser URL, while acknowledgement advances local watermarks on close.
//
// Unread state is read here but never advanced here: the watermark moves when
// this panel closes, so the rows you opened it to read stay marked while you
// read them.
Surface {
    id: root

    // The host hands us the usable envelope of the output it is drawn on; the
    // defaults stand in for a host that sets neither.
    availableWidth: Theme.popWidth
    availableHeight: 800 - Theme.barTopMargin - Theme.barHeight - 16

    readonly property int headerHeight: Theme.rowHeight
    readonly property int footerHeight: Theme.rowHeight
    readonly property int dividerHeight: 13
    readonly property int maxBodyHeight: Math.max(220, root.availableHeight
        - root.padding * 2 - headerHeight - footerHeight - dividerHeight)

    property string page: "inbox"
    property string selectedSlug: ""
    property string expandedSha: ""
    property bool settledExpanded: false

    // Every relative label on screen is derived from this rather than from
    // Date.now() at binding time, so they all age together and none of them
    // needs its own timer.
    property double now: Date.now()

    readonly property var visibleRepos: Helpers.displayedRepos(GitHub.repos, GitHub.opts.repos)
    readonly property var inboxRows: GitHub.inboxItems
    readonly property var inboxSections: Helpers.inboxSections(root.inboxRows)
    readonly property var selectedRepo: GitHub.repos.find(r => r.slug === root.selectedSlug)
        ?? null
    readonly property var commitEntry: GitHub.commitCache[root.selectedSlug] ?? null
    readonly property var commitRows: root.commitEntry ? root.commitEntry.rows : []
    readonly property int newCommitCount: Helpers.newCommits(root.commitRows, GitHub.seenAt)

    function showInbox() {
        page = "inbox";
        expandedSha = "";
    }

    function showRepos() {
        page = "repos";
        expandedSha = "";
    }

    function showCommits(slug) {
        selectedSlug = slug;
        expandedSha = "";
        page = "commits";
        GitHub.requestCommits(slug, false);
    }

    function toggleCommit(sha) {
        if (expandedSha === sha) {
            expandedSha = "";
            return;
        }
        expandedSha = sha;
        GitHub.requestStats(root.selectedSlug, sha);
    }

    // Commits always backs out to Repositories. Either top-level tab lets the
    // host consume Escape and close the popover.
    function handleEscape(): bool {
        if (page !== "commits")
            return false;
        showRepos();
        return true;
    }

    function openInbox(row) {
        if (row && row.url) {
            GitHub.open(row.url);
            Popouts.close();
        }
    }

    function toneColor(tone) {
        switch (tone) {
        case "red": return Theme.red;
        case "amber": return Theme.amber;
        case "green": return Theme.connected;
        case "accent": return Theme.accent;
        default: return Theme.textDim;
        }
    }

    function toneFill(tone) {
        switch (tone) {
        case "red": return Theme.redBgSoft;
        case "amber": return Theme.amberBgSoft;
        case "accent": return Theme.accentBgSoft;
        default: return Theme.cardFill;
        }
    }

    function inboxStatus(row) {
        if (row.kind === "run")
            return Helpers.runStatusLabel(row.status, row.conclusion);
        if (row.kind === "notification")
            return "directed";
        if (row.kind === "discussion")
            return "new";
        return row.status || "update";
    }

    function inboxMeta(row) {
        const parts = [row.repo];
        if (row.kind === "run") {
            if (row.branch)
                parts.push(row.branch + (row.event ? " / " + row.event : ""));
            else if (row.event)
                parts.push(row.event);
            if (row.actor)
                parts.push("@" + row.actor);
            if (row.number > 0)
                parts.push("#" + row.number);
        }
        const when = Helpers.inboxTimeLabel(row, root.now);
        if (when)
            parts.push(when);
        return parts.join(" · ");
    }

    // What was last copied, so whichever control did it can confirm — the
    // Tailscale popover's `copiedIp` shape, because a clipboard write is
    // otherwise completely silent. One property for both copy actions, so
    // they cannot disagree about how long the confirmation lasts.
    property string copied: ""

    function copy(text) {
        if (typeof text !== "string" || text === "")
            return;
        GitHub.copy(text);
        copied = text;
        copiedReset.restart();
    }

    Timer {
        id: copiedReset
        interval: 1600
        onTriggered: root.copied = ""
    }

    // The feed is refreshed on open when it is old enough to be worth it, and
    // everything on screen is marked read when the panel goes away — which is
    // what "since the popover was last open" means.
    Claim {
        active: root.visible
        onClaimed: {
            root.showInbox();
            root.now = Date.now();
            GitHub.refreshIfStale(30000);
        }
        onReleased: GitHub.markSeen()
    }

    Timer {
        interval: 30000
        running: root.visible
        repeat: true
        onTriggered: root.now = Date.now()
    }

    // ---- shared row parts -------------------------------------------------

    // "owner/" dim, name bright, and only the name elides — the owner is the
    // short half and losing it costs more than losing the tail of a long
    // repository name.
    component RepoName: Item {
        id: nameBox

        property string owner: ""
        property string name: ""
        property bool strong: false

        Text {
            id: ownerText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: nameBox.owner + "/"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontBody
            color: Theme.textDim
        }

        Text {
            anchors.left: ownerText.right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: nameBox.name
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontBody
            font.weight: nameBox.strong ? Theme.weightMedium : Theme.weightRegular
            color: nameBox.strong ? Theme.textHi : Theme.textMid
            elide: Text.ElideRight
        }
    }

    component UnreadDot: Rectangle {
        property bool unread: false

        width: 7
        height: 7
        radius: 4
        color: unread ? Theme.accent : Theme.dotDim
    }

    component Empty: Text {
        width: parent ? parent.width : 0
        topPadding: 14
        bottomPadding: 14
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontSecondary
        color: Theme.textDim
    }

    component TabButton: Rectangle {
        id: tab

        property string label: ""
        property string pageName: ""
        readonly property bool selected: root.page === pageName

        width: tabText.implicitWidth + 22
        height: Theme.controlHeight
        radius: 7
        color: selected ? Theme.accentBg
            : tabMouse.containsMouse || activeFocus ? Theme.hoverFill : "transparent"
        border.width: activeFocus ? 1 : 0
        border.color: Theme.accent
        activeFocusOnTab: visible
        Accessible.role: Accessible.PageTab
        Accessible.name: label
        Accessible.selected: selected
        Accessible.onPressAction: {
            if (pageName === "inbox")
                root.showInbox();
            else
                root.showRepos();
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                if (tab.pageName === "inbox")
                    root.showRepos();
                else
                    root.showInbox();
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                if (tab.pageName === "inbox")
                    root.showInbox();
                else
                    root.showRepos();
                event.accepted = true;
            }
        }

        Text {
            id: tabText
            anchors.centerIn: parent
            text: tab.label
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontSecondary
            font.weight: tab.selected ? Theme.weightSemibold : Theme.weightRegular
            color: tab.selected ? Theme.accent : Theme.textLow
        }

        MouseArea {
            id: tabMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                tab.forceActiveFocus();
                if (tab.pageName === "inbox")
                    root.showInbox();
                else
                    root.showRepos();
            }
        }
    }

    component InboxCard: Rectangle {
        id: inboxCard

        required property var row
        readonly property bool actionsRevealed: inboxHover.hovered || activeFocus
            || settleAction.activeFocus

        width: parent ? parent.width - 4 : 0
        x: 2
        height: 66
        radius: Theme.rowRadius
        color: inboxHover.hovered || activeFocus ? Theme.hoverFillStrong
            : row.active || row.unread ? root.toneFill(row.tone) : "transparent"
        border.width: activeFocus ? 1 : 0
        border.color: root.toneColor(row.tone)
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: row.title + ", " + row.detail + ", "
            + root.inboxStatus(row)
        Accessible.description: "Open on GitHub"
        Accessible.onPressAction: root.openInbox(row)

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                root.openInbox(inboxCard.row);
                event.accepted = true;
            }
        }

        // Unlike MouseArea.containsMouse, the handler remains hovered while
        // the pointer crosses into the child Settle/Unsettle button.
        HoverHandler {
            id: inboxHover
        }

        // Kept below the inline action in stacking order: settling consumes
        // only its own click, while every other point still opens GitHub.
        MouseArea {
            id: inboxMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                inboxCard.forceActiveFocus();
                root.openInbox(inboxCard.row);
            }
        }

        Rectangle {
            id: inboxDot
            anchors.left: parent.left
            anchors.leftMargin: 10
            y: 12
            width: 8
            height: 8
            radius: 4
            color: root.toneColor(inboxCard.row.tone)
        }

        Item {
            id: inboxSide
            anchors.right: parent.right
            anchors.rightMargin: 9
            y: 6
            width: inboxCard.actionsRevealed && inboxCard.row.canSettle
                ? settleAction.width : statusPill.width
            height: 20

            Rectangle {
                id: statusPill
                visible: !inboxCard.actionsRevealed || !inboxCard.row.canSettle
                anchors.right: parent.right
                width: statusLabel.implicitWidth + 10
                height: 20
                radius: 5
                color: root.toneFill(inboxCard.row.tone)

                Text {
                    id: statusLabel
                    anchors.centerIn: parent
                    text: root.inboxStatus(inboxCard.row)
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    font.weight: Theme.weightSemibold
                    color: root.toneColor(inboxCard.row.tone)
                }
            }

            ActionButton {
                id: settleAction
                visible: inboxCard.row.canSettle && inboxCard.actionsRevealed
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: inboxCard.row.lifecycle === "settled" ? "Unsettle" : "Settle"
                tint: Theme.accent
                fill: Theme.accentBg
                hPadding: 16
                revealed: inboxCard.actionsRevealed
                onTriggered: {
                    if (inboxCard.row.lifecycle === "settled")
                        GitHub.unsettleInboxItem(inboxCard.row.key);
                    else
                        GitHub.settleInboxItem(inboxCard.row.key);
                }
            }
        }

        Text {
            anchors.left: inboxDot.right
            anchors.leftMargin: 9
            anchors.right: inboxSide.left
            anchors.rightMargin: 8
            y: 6
            text: inboxCard.row.title
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontBody
            font.weight: inboxCard.row.unread || inboxCard.row.active
                ? Theme.weightSemibold : Theme.weightMedium
            color: Theme.textHi
            elide: Text.ElideRight
        }

        Text {
            anchors.left: inboxDot.right
            anchors.leftMargin: 9
            anchors.right: parent.right
            anchors.rightMargin: 10
            y: 26
            text: inboxCard.row.detail
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontSecondary
            color: Theme.textLow
            elide: Text.ElideRight
        }

        Text {
            anchors.left: inboxDot.right
            anchors.leftMargin: 9
            anchors.right: parent.right
            anchors.rightMargin: 10
            y: 46
            text: root.inboxMeta(inboxCard.row)
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: Theme.textDim
            elide: Text.ElideRight
        }

    }

    // ---- header -----------------------------------------------------------
    Item {
        width: parent.width
        height: root.headerHeight

        Item {
            id: topLevelHeader
            visible: root.page !== "commits"
            anchors.fill: parent

            Row {
                id: topTabs
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                TabButton {
                    label: "Inbox"
                    pageName: "inbox"
                }

                TabButton {
                    label: "Repositories"
                    pageName: "repos"
                }
            }

            Rectangle {
                id: refreshButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: Theme.controlHeight
                radius: 6
                color: refreshMouse.containsMouse || activeFocus
                    ? Theme.hoverFill : "transparent"
                border.width: activeFocus ? 1 : 0
                border.color: Theme.accent
                activeFocusOnTab: visible
                Accessible.role: Accessible.Button
                Accessible.name: "Refresh GitHub repositories and Inbox"
                Accessible.onPressAction: GitHub.refreshAll()

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                            || event.key === Qt.Key_Space) {
                        GitHub.refreshAll();
                        event.accepted = true;
                    }
                }

                Sym {
                    anchors.centerIn: parent
                    name: "refresh" // nf-fa-rotate
                    size: Theme.iconSmall
                    color: GitHub.polling || GitHub.inboxPolling
                        ? Theme.accent : Theme.textLow
                }

                MouseArea {
                    id: refreshMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        refreshButton.forceActiveFocus();
                        GitHub.refreshAll();
                    }
                }
            }

            Text {
                anchors.left: topTabs.right
                anchors.leftMargin: 6
                anchors.right: refreshButton.left
                anchors.rightMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: {
                    const busy = root.page === "inbox"
                        ? GitHub.inboxPolling : GitHub.polling;
                    const checked = root.page === "inbox"
                        ? GitHub.inboxCheckedAt : GitHub.checkedAt;
                    if (busy)
                        return "checking…";
                    return checked > 0 ? Helpers.agoLabel(checked, root.now) : "";
                }
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: Theme.textDim
                elide: Text.ElideLeft
            }
        }

        // Commit list: back, the repository, and a way out to the browser.
        ActionButton {
            id: backAction
            visible: root.page === "commits"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            label: "‹ Repos"
            hPadding: 20
            revealed: visible
            onTriggered: root.showRepos()
        }

        RepoName {
            visible: root.page === "commits"
            anchors.left: backAction.right
            anchors.leftMargin: 8
            anchors.right: copyRepoLink.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            owner: root.selectedRepo ? root.selectedRepo.owner : ""
            name: root.selectedRepo ? root.selectedRepo.name : ""
            strong: true
        }

        // Copies the repository's URL, beside the link that opens it. The
        // glyph becomes a tick for as long as `copied` holds, because a
        // clipboard write has nothing else to show for itself.
        Rectangle {
            id: copyRepoLink

            readonly property string url: GitHub.repoUrl(root.selectedSlug)
            readonly property bool confirmed: root.copied !== "" && root.copied === url

            visible: root.page === "commits"
            anchors.right: openRepoLink.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 27
            height: Theme.controlHeight
            radius: 6
            color: copyMouse.containsMouse || activeFocus ? Theme.hoverFill : "transparent"
            border.width: activeFocus ? 1 : 0
            border.color: Theme.accent
            activeFocusOnTab: visible
            Accessible.role: Accessible.Button
            Accessible.name: "Copy repository URL"
            Accessible.onPressAction: root.copy(copyRepoLink.url)

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                        || event.key === Qt.Key_Space) {
                    root.copy(copyRepoLink.url);
                    event.accepted = true;
                }
            }

            Sym {
                anchors.centerIn: parent
                // nf-fa-check / nf-fa-copy
                name: copyRepoLink.confirmed ? "check" : "content_copy"
                size: Theme.iconSmall
                color: copyRepoLink.confirmed ? Theme.accent
                    : copyMouse.containsMouse ? Theme.textMid : Theme.textLow
            }

            MouseArea {
                id: copyMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    copyRepoLink.forceActiveFocus();
                    root.copy(copyRepoLink.url);
                }
            }
        }

        LinkText {
            id: openRepoLink
            visible: root.page === "commits"
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Open ↗"
            onClicked: {
                GitHub.open(GitHub.repoUrl(root.selectedSlug));
                Popouts.close();
            }
        }
    }

    // ---- body -------------------------------------------------------------
    Flickable {
        id: body

        width: parent.width
        height: Math.min(contentHeight, root.maxBodyHeight)
        contentWidth: width
        contentHeight: pageLoader.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        activeFocusOnTab: interactive

        // Deliberately synchronous: this popover's implicit height is this
        // page's height, and the host animates its geometry from it. An
        // incubating page measures as zero, which opens the body in two
        // stages and collapses it on every navigation.
        Loader {
            id: pageLoader
            width: body.width - (body.contentHeight > body.height ? 5 : 0)
            sourceComponent: root.page === "commits" ? commitsPage
                : root.page === "repos" ? reposPage : inboxPage
            height: item ? item.implicitHeight : 0
        }
    }

    // ---- footer -----------------------------------------------------------
    HDivider {}

    Item {
        width: parent.width
        height: root.footerHeight

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            // The repository list has no footer action, so its caption takes
            // the whole width rather than stopping at a link that is not there.
            anchors.right: footerLink.visible ? footerLink.left : parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: {
                if (root.page === "commits") {
                    const branch = root.selectedRepo ? root.selectedRepo.branch : "";
                    return root.commitRows.length + " latest · " + branch
                        + " · click a commit to expand";
                }
                if (root.page === "inbox") {
                    if (GitHub.inboxError !== "")
                        return "Inbox paused · cached items kept";
                    return GitHub.pendingInboxCount + " pending · "
                        + GitHub.settledInboxCount + " settled";
                }
                if (GitHub.error !== "")
                    return "feed unavailable";
                return root.visibleRepos.length
                    + " recent + watched repos · click a repo for commits";
            }
            elide: Text.ElideRight
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontSecondary
            color: Theme.textDim
        }

        LinkText {
            id: footerLink
            visible: root.page === "commits"
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Open repo ↗"
            onClicked: {
                GitHub.open(GitHub.repoUrl(root.selectedSlug));
                Popouts.close();
            }
        }
    }

    // ---- Inbox ------------------------------------------------------------
    Component {
        id: inboxPage

        Column {
            id: inboxList

            readonly property var failedWorkflows: Object.keys(GitHub.workflowRepoErrors)
            readonly property var failedEvents: Object.keys(GitHub.eventRepoErrors)

            width: pageLoader.width

            Empty {
                visible: GitHub.inboxError !== ""
                text: "Inbox temporarily paused\n" + GitHub.inboxError
                color: Theme.redText
            }

            Empty {
                visible: GitHub.notificationError !== ""
                text: "Notifications unavailable · " + GitHub.notificationError
                color: Theme.amber
            }

            Empty {
                visible: inboxList.failedWorkflows.length > 0
                text: "Workflows unavailable for " + inboxList.failedWorkflows.length
                    + (inboxList.failedWorkflows.length === 1 ? " repository · "
                        : " repositories · ")
                    + inboxList.failedWorkflows.slice(0, 3).join(", ")
                color: Theme.amber
            }

            Empty {
                visible: inboxList.failedEvents.length > 0
                text: "Repository events unavailable for " + inboxList.failedEvents.length
                    + (inboxList.failedEvents.length === 1 ? " repository · "
                        : " repositories · ")
                    + inboxList.failedEvents.slice(0, 3).join(", ")
                color: Theme.amber
            }

            Empty {
                visible: !GitHub.inboxReady && root.inboxRows.length === 0
                    && GitHub.inboxError === ""
                text: GitHub.ciReportsEnabled
                    ? "Loading workflows, notifications, and repository updates…"
                    : "Loading notifications and repository updates…"
            }

            Empty {
                visible: GitHub.inboxReady && root.inboxRows.length === 0
                    && GitHub.inboxError === "" && GitHub.notificationError === ""
                text: GitHub.ciReportsEnabled
                    ? "Inbox is clear"
                    : "Inbox is clear\nWorkflow reports are disabled in settings"
            }

            // Active, Attention, Updates, Settled. Only the retained settled
            // history starts collapsed; every pending entity stays visible.
            Repeater {
                model: root.inboxSections

                delegate: Column {
                    id: inboxSection

                    required property var modelData

                    visible: modelData.rows.length > 0
                    width: inboxList.width

                    SectionLabel {
                        // No explicit height: the Column already drops an
                        // invisible child, and reading `implicitHeight` back
                        // into `height` on a Text is a binding loop — one the
                        // machine check greps the journal for.
                        visible: inboxSection.modelData.id !== "settled"
                        width: parent.width
                        text: inboxSection.modelData.title.toUpperCase()
                            + " · " + inboxSection.modelData.rows.length
                    }

                    Rectangle {
                        id: settledDrawer
                        visible: inboxSection.modelData.id === "settled"
                        width: parent.width
                        height: visible ? Theme.controlHeight + 4 : 0
                        radius: 6
                        color: settledMouse.containsMouse || activeFocus
                            ? Theme.hoverFill : "transparent"
                        border.width: activeFocus ? 1 : 0
                        border.color: Theme.accent
                        activeFocusOnTab: visible
                        Accessible.role: Accessible.Button
                        Accessible.name: "Settled, " + inboxSection.modelData.rows.length
                            + " items, " + (root.settledExpanded ? "expanded" : "collapsed")
                        Accessible.onPressAction: root.settledExpanded = !root.settledExpanded

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                    || event.key === Qt.Key_Space) {
                                root.settledExpanded = !root.settledExpanded;
                                event.accepted = true;
                            }
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 9
                            anchors.verticalCenter: parent.verticalCenter
                            text: (root.settledExpanded ? "⌄ " : "› ") + "SETTLED · "
                                + inboxSection.modelData.rows.length
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontCaption
                            font.weight: Theme.weightSemibold
                            color: Theme.textDim
                        }

                        MouseArea {
                            id: settledMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                settledDrawer.forceActiveFocus();
                                root.settledExpanded = !root.settledExpanded;
                            }
                        }
                    }

                    Repeater {
                        model: inboxSection.modelData.id !== "settled" || root.settledExpanded
                            ? inboxSection.modelData.rows : []

                        delegate: InboxCard {
                            required property var modelData
                            row: modelData
                        }
                    }
                }
            }
        }
    }

    // ---- repositories -----------------------------------------------------
    Component {
        id: reposPage

        Column {
            id: repoList

            width: pageLoader.width

            Empty {
                visible: GitHub.error !== ""
                text: "GitHub unavailable\n" + GitHub.error
                color: Theme.redText
            }

            Empty {
                visible: Object.keys(GitHub.watchErrors).length > 0
                text: Object.keys(GitHub.watchErrors).length === 1
                    ? "1 watched repository is unavailable · "
                        + Object.keys(GitHub.watchErrors)[0]
                    : Object.keys(GitHub.watchErrors).length
                        + " watched repositories are unavailable"
                color: Theme.amber
            }

            Empty {
                visible: GitHub.error === "" && !GitHub.ready
                text: "Loading repositories…"
            }

            Empty {
                visible: GitHub.error === "" && GitHub.ready && GitHub.repos.length === 0
                text: "No repositories this account can see"
            }

            Repeater {
                model: root.visibleRepos

                // A wrapper, so the band rule sits outside the row's own hover
                // pill rather than making it 13px taller than every other one.
                delegate: Item {
                    id: repoEntry

                    required property var modelData
                    required property int index

                    readonly property bool unread: modelData.pushedAt !== ""
                        && GitHub.seenAt !== "" && modelData.pushedAt > GitHub.seenAt
                    readonly property bool bandBreak: index > 0
                        && Helpers.bucketBreak(modelData.pushedAt,
                            root.visibleRepos[index - 1].pushedAt, root.now)

                    width: repoList.width
                    height: repoBand.height + Theme.rowHeight

                    HDivider {
                        id: repoBand
                        visible: repoEntry.bandBreak
                        height: visible ? root.dividerHeight : 0
                    }

                Rectangle {
                    id: repoRow

                    readonly property var modelData: repoEntry.modelData
                    readonly property bool unread: repoEntry.unread

                    x: 2
                    y: repoBand.height
                    width: repoEntry.width - 4
                    height: Theme.rowHeight
                    radius: Theme.rowRadius
                    color: repoMouse.containsMouse || activeFocus
                        ? Theme.hoverFill : "transparent"
                    border.width: activeFocus ? 1 : 0
                    border.color: Theme.accent
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: repoRow.modelData.slug
                        + (repoRow.unread ? ", updated" : "")
                        + (GitHub.watchError(repoRow.modelData.slug) !== ""
                            ? ", Inbox data unavailable" : "")
                    Accessible.description: "Show commits"
                    Accessible.onPressAction: root.showCommits(repoRow.modelData.slug)

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                || event.key === Qt.Key_Space) {
                            root.showCommits(repoRow.modelData.slug);
                            event.accepted = true;
                        }
                    }

                    UnreadDot {
                        id: repoDot
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        unread: repoRow.unread
                    }

                    Text {
                        id: repoTime
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: Helpers.relTime(repoRow.modelData.pushedAt, root.now)
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontCaption
                        color: Theme.textDim
                    }

                    Row {
                        id: repoTail
                        anchors.right: repoTime.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Sym {
                            visible: GitHub.watchError(repoRow.modelData.slug) !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            name: "warning" // nf-fa-triangle-exclamation
                            size: Theme.iconSmall
                            color: Theme.amber
                        }

                        Rectangle {
                            visible: repoRow.modelData.watched
                            anchors.verticalCenter: parent.verticalCenter
                            width: watchLabel.implicitWidth + 10
                            height: watchLabel.implicitHeight + 4
                            radius: 4
                            color: Theme.accentBgSoft

                            Text {
                                id: watchLabel
                                anchors.centerIn: parent
                                text: "WATCHING"
                                font.family: Theme.fontMenu
                                font.pixelSize: Theme.fontCaption
                                font.weight: Theme.weightSemibold
                                font.letterSpacing: 0.5
                                color: Theme.accent
                            }
                        }

                        Sym {
                            visible: repoRow.modelData.isPrivate
                            anchors.verticalCenter: parent.verticalCenter
                            name: "lock" // nf-fa-lock
                            size: Theme.iconSmall
                            color: Theme.textDim
                        }
                    }

                    RepoName {
                        anchors.left: repoDot.right
                        anchors.leftMargin: 10
                        anchors.right: repoTail.left
                        anchors.rightMargin: repoTail.width > 0 ? 10 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height
                        owner: repoRow.modelData.owner
                        name: repoRow.modelData.name
                        strong: repoRow.unread
                    }

                    MouseArea {
                        id: repoMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            repoRow.forceActiveFocus();
                            root.showCommits(repoRow.modelData.slug);
                        }
                    }
                }
                }
            }
        }
    }

    // ---- commits ----------------------------------------------------------
    Component {
        id: commitsPage

        Column {
            id: commitList

            width: pageLoader.width

            // What changed since you last looked, in the same terms the
            // repository row's dot used.
            Item {
                width: parent.width
                height: 22

                Row {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Text {
                        text: (root.selectedRepo ? root.selectedRepo.branch : "") + " · "
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontSecondary
                        color: Theme.textDim
                    }

                    Text {
                        visible: root.newCommitCount > 0
                        text: root.newCommitCount
                            + (root.newCommitCount === 1 ? " new commit" : " new commits")
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontSecondary
                        color: Theme.accent
                    }

                    Text {
                        text: root.newCommitCount > 0 ? " since you last looked"
                            : "nothing new since you last looked"
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontSecondary
                        color: Theme.textDim
                    }
                }
            }

            Empty {
                visible: root.commitEntry !== null && root.commitEntry.error !== ""
                text: "Commits unavailable\n"
                    + (root.commitEntry ? root.commitEntry.error : "")
                color: Theme.redText
            }

            Empty {
                visible: root.commitEntry === null
                    || (root.commitEntry.loading && root.commitRows.length === 0)
                text: "Loading commits…"
            }

            Empty {
                visible: root.commitEntry !== null && !root.commitEntry.loading
                    && root.commitEntry.error === "" && root.commitRows.length === 0
                text: "No commits on this branch yet"
            }

            Repeater {
                model: root.commitRows

                delegate: Item {
                    id: commitRow

                    required property var modelData
                    required property int index

                    readonly property bool expanded: root.expandedSha === modelData.sha
                    readonly property bool unread: modelData.date !== ""
                        && GitHub.seenAt !== "" && modelData.date > GitHub.seenAt
                    readonly property var stats: GitHub.statsCache[modelData.sha] ?? null
                    readonly property bool bandBreak: index > 0
                        && Helpers.bucketBreak(modelData.date,
                            root.commitRows[index - 1].date, root.now)

                    width: commitList.width
                    height: commitBand.height + (expanded ? expandedCard.height + 6 : 52)

                    HDivider {
                        id: commitBand
                        visible: commitRow.bandBreak
                        height: visible ? root.dividerHeight : 0
                    }

                    // Collapsed: subject on one line, provenance under it.
                    Rectangle {
                        id: collapsed
                        visible: !commitRow.expanded
                        x: 2
                        y: commitBand.height
                        width: parent.width - 4
                        height: 52
                        radius: Theme.rowRadius
                        color: collapsedMouse.containsMouse || activeFocus
                            ? Theme.hoverFill : "transparent"
                        border.width: activeFocus ? 1 : 0
                        border.color: Theme.accent
                        activeFocusOnTab: visible
                        Accessible.role: Accessible.Button
                        Accessible.name: commitRow.modelData.subject
                        Accessible.description: "Expand commit"
                        Accessible.onPressAction: root.toggleCommit(commitRow.modelData.sha)

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                    || event.key === Qt.Key_Space) {
                                root.toggleCommit(commitRow.modelData.sha);
                                event.accepted = true;
                            }
                        }

                        UnreadDot {
                            id: collapsedDot
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            unread: commitRow.unread
                        }

                        Column {
                            anchors.left: collapsedDot.right
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                width: parent.width
                                text: commitRow.modelData.subject
                                font.family: Theme.fontMenu
                                font.pixelSize: Theme.fontBody
                                font.weight: commitRow.unread
                                    ? Theme.weightMedium : Theme.weightRegular
                                color: commitRow.unread ? Theme.textHi : Theme.textMid
                                elide: Text.ElideRight
                            }

                            Row {
                                spacing: 0

                                Text {
                                    text: commitRow.modelData.short
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontCaption
                                    color: Theme.textDim
                                }

                                Text {
                                    text: " · " + commitRow.modelData.author + " · "
                                        + Helpers.agoLabelIso(commitRow.modelData.date, root.now)
                                    font.family: Theme.fontMenu
                                    font.pixelSize: Theme.fontCaption
                                    color: Theme.textDim
                                }
                            }
                        }

                        MouseArea {
                            id: collapsedMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                collapsed.forceActiveFocus();
                                root.toggleCommit(commitRow.modelData.sha);
                            }
                        }
                    }

                    // Expanded: the full message, what it touched, and the two
                    // things there are to do with a commit from here.
                    Rectangle {
                        id: expandedCard
                        visible: commitRow.expanded
                        x: 2
                        y: commitBand.height + 4
                        width: parent.width - 4
                        height: cardBody.implicitHeight + 24
                        radius: Theme.rowRadius
                        color: Theme.cardFill

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleCommit(commitRow.modelData.sha)
                        }

                        Column {
                            id: cardBody
                            x: 12
                            y: 12
                            width: parent.width - 24
                            spacing: 0

                            Row {
                                width: parent.width
                                spacing: 10

                                UnreadDot {
                                    y: 5
                                    unread: commitRow.unread
                                }

                                Text {
                                    width: parent.width - 17
                                    text: commitRow.modelData.subject
                                    font.family: Theme.fontMenu
                                    font.pixelSize: Theme.fontBody
                                    font.weight: Theme.weightMedium
                                    color: Theme.textHi
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Text {
                                visible: commitRow.modelData.body !== ""
                                x: 17
                                width: parent.width - 17
                                topPadding: 7
                                text: commitRow.modelData.body
                                font.family: Theme.fontMenu
                                font.pixelSize: Theme.fontSecondary
                                lineHeight: Theme.proseLineHeight
                                color: Theme.textLow
                                wrapMode: Text.WordWrap
                                // Enough for the first paragraph of a real
                                // commit message; the rest is what "Open on
                                // GitHub" is for.
                                maximumLineCount: 4
                                elide: Text.ElideRight
                            }

                            // Statistics left, provenance right — until they
                            // do not both fit, which a five-figure diff or a
                            // long account name is enough to cause, and then
                            // the provenance takes its own line under them.
                            // Two absolutely positioned halves of one row is
                            // what let "−39641" and "CybexFleetBootstrap"
                            // render on top of each other.
                            Item {
                                id: metaBox

                                readonly property real gap: 10
                                readonly property bool stacked: metaRow.implicitWidth
                                    + gap + metaAuthor.implicitWidth > width

                                x: 17
                                width: parent.width - 17
                                height: 9 + metaRow.implicitHeight
                                    + (stacked ? 2 + metaAuthor.implicitHeight : 0)

                                Row {
                                    id: metaRow
                                    y: 9
                                    spacing: metaBox.gap

                                    Text {
                                        text: commitRow.modelData.short
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontCaption
                                        color: Theme.textDim
                                    }

                                    Text {
                                        visible: commitRow.stats !== null
                                        text: commitRow.stats
                                            ? commitRow.stats.files
                                                + (commitRow.stats.files === 1 ? " file" : " files")
                                            : ""
                                        font.family: Theme.fontMenu
                                        font.pixelSize: Theme.fontCaption
                                        color: Theme.textDim
                                    }

                                    Text {
                                        visible: commitRow.stats !== null
                                        text: commitRow.stats ? "+" + commitRow.stats.additions : ""
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontCaption
                                        font.weight: Theme.weightMedium
                                        color: Theme.connected
                                    }

                                    Text {
                                        visible: commitRow.stats !== null
                                        text: commitRow.stats ? "−" + commitRow.stats.deletions : ""
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontCaption
                                        font.weight: Theme.weightMedium
                                        color: Theme.redText
                                    }

                                    Text {
                                        visible: commitRow.stats === null
                                        text: "counting…"
                                        font.family: Theme.fontMenu
                                        font.pixelSize: Theme.fontCaption
                                        color: Theme.textFaint
                                    }
                                }

                                Text {
                                    id: metaAuthor

                                    // Stacked it lines up under the sha as a
                                    // second meta line; inline it stays the
                                    // right-hand column. Never wider than the
                                    // card, so an account name long enough to
                                    // overflow elides instead.
                                    x: metaBox.stacked ? 0 : metaBox.width - width
                                    y: metaBox.stacked ? metaRow.y + metaRow.height + 2 : 9
                                    width: Math.min(implicitWidth, metaBox.width)
                                    text: commitRow.modelData.author + " · "
                                        + Helpers.agoLabelIso(commitRow.modelData.date, root.now)
                                    elide: Text.ElideRight
                                    font.family: Theme.fontMenu
                                    font.pixelSize: Theme.fontCaption
                                    color: Theme.textDim
                                }
                            }

                            Row {
                                x: 17
                                topPadding: 11
                                spacing: 6

                                ActionButton {
                                    label: "Open on GitHub"
                                    hPadding: 24
                                    revealed: commitRow.expanded
                                    onTriggered: {
                                        GitHub.open(commitRow.modelData.url !== ""
                                            ? commitRow.modelData.url
                                            : GitHub.repoUrl(root.selectedSlug)
                                                + "/commit/" + commitRow.modelData.sha);
                                        Popouts.close();
                                    }
                                }

                                ActionButton {
                                    readonly property bool confirmed: root.copied !== ""
                                        && root.copied === commitRow.modelData.sha

                                    label: confirmed ? "Copied" : "Copy SHA"
                                    tint: confirmed ? Theme.accent : Theme.textLow
                                    hPadding: 24
                                    revealed: commitRow.expanded
                                    onTriggered: root.copy(commitRow.modelData.sha)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // The host reuses this panel's slot, so navigation is reset here rather
    // than relying on a fresh instance per open.
    Component.onCompleted: root.showInbox()
}
