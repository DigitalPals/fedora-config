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

    // Match the integrated T3 workspace: the module owns a calm canvas and
    // composes raised cards inside it, while the popout host still owns the
    // outer shadow and opening motion.
    spacing: 6
    padding: T3Theme.pagePadding
    surfaceColor: T3Theme.canvas
    surfaceBorderColor: T3Theme.borderStrong

    // The host hands us the usable envelope of the output it is drawn on; the
    // defaults stand in for a host that sets neither.
    availableWidth: 484 - Theme.barSideMargin * 2
    availableHeight: 800 - Theme.barTopMargin - Theme.barHeight - 16
    implicitWidth: Math.max(Theme.t3MinWidth, Math.min(460, root.availableWidth))

    readonly property int headerHeight: T3Theme.headerHeight
    readonly property int footerHeight: T3Theme.footerHeight
    readonly property int dividerHeight: 13
    readonly property int maxBodyHeight: Math.max(220, root.availableHeight
        - root.padding * 2 - headerHeight - footerHeight - root.spacing * 2)

    property string page: "inbox"
    property string selectedSlug: ""
    property string expandedSha: ""
    property bool settledExpanded: false
    property string repoSearchText: ""

    // Every relative label on screen is derived from this rather than from
    // Date.now() at binding time, so they all age together and none of them
    // needs its own timer.
    property double now: Date.now()

    readonly property var visibleRepos: Helpers.displayedRepos(GitHub.repos, GitHub.opts.repos)
    readonly property var filteredRepos: {
        const query = root.repoSearchText.trim().toLowerCase();
        if (query === "")
            return root.visibleRepos;
        return root.visibleRepos.filter(repo => [repo.slug, repo.owner, repo.name,
            repo.branch].some(value => String(value ?? "").toLowerCase().includes(query)));
    }
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
        if (page === "repos" && repoSearchText !== "") {
            repoSearchText = "";
            return true;
        }
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
        case "red": return T3Theme.red;
        case "amber": return T3Theme.amber;
        case "green": return T3Theme.success;
        case "accent": return T3Theme.accent;
        default: return T3Theme.textFaint;
        }
    }

    function toneFill(tone) {
        switch (tone) {
        case "red": return T3Theme.redSoft;
        case "amber": return T3Theme.amberSoft;
        case "accent": return T3Theme.accentSubtle;
        default: return T3Theme.surface;
        }
    }

    function inboxIcon(row) {
        switch (row.kind) {
        case "run": return "deployed_code";
        case "notification": return "notifications";
        case "pull_request": return "merge";
        case "issue": return "adjust";
        case "push": return "commit";
        case "ref": return row.refType === "tag" ? "sell" : "fork_right";
        case "release": return "rocket_launch";
        case "discussion": return "forum";
        default: return "change_circle";
        }
    }

    function inboxStatusIcon(row) {
        if (row.active)
            return "sync";
        if (row.tone === "red")
            return "error";
        if (row.tone === "amber")
            return "priority_high";
        if (row.tone === "green")
            return "check_circle";
        return row.lifecycle === "settled" ? "archive" : "change_circle";
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
            font.family: T3Theme.fontUi
            font.pixelSize: Theme.fontBody
            color: T3Theme.textFaint
        }

        Text {
            anchors.left: ownerText.right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: nameBox.name
            font.family: T3Theme.fontUi
            font.pixelSize: Theme.fontBody
            font.weight: nameBox.strong ? Theme.weightMedium : Theme.weightRegular
            color: nameBox.strong ? T3Theme.textPrimary : T3Theme.textSecondary
            elide: Text.ElideRight
        }
    }

    component UnreadDot: Rectangle {
        property bool unread: false

        width: 7
        height: 7
        radius: 4
        color: unread ? T3Theme.accent : Theme.dotDim
    }

    component Empty: Text {
        width: parent ? parent.width : 0
        topPadding: 14
        bottomPadding: 14
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        font.family: T3Theme.fontUi
        font.pixelSize: Theme.fontSecondary
        color: T3Theme.textFaint
    }

    component Action: ActionButton {
        fontFamily: T3Theme.fontUi
        focusColor: T3Theme.focus
        buttonRadius: T3Theme.controlRadius
        tint: T3Theme.textMuted
        fill: T3Theme.hover
    }

    component GitHubStatus: StatusPlaceholder {
        fontFamily: T3Theme.fontUi
        accentColor: T3Theme.accent
        accentFill: T3Theme.accentSubtle
        outlineColor: T3Theme.border
        primaryTextColor: T3Theme.textSecondary
        secondaryTextColor: T3Theme.textFaint
        errorColor: T3Theme.red
        errorFill: T3Theme.redSoft
        errorOutline: T3Theme.redBorder
        transitionDuration: T3Theme.normalDuration
        fadeDuration: T3Theme.fastDuration
    }

    component GroupHeader: Item {
        id: group

        property string label: ""
        property int count: 0
        property color tint: T3Theme.textMuted
        property color rule: T3Theme.border

        width: parent ? parent.width : 0
        height: Theme.sectionHeaderHeight + 8

        // The shared section mark: uppercase micro label, count, hairline to
        // the edge. Settings/SectionHeader.qml and T3's inbox draw the same
        // shape — one grammar across every dialog is the point.
        Text {
            id: groupLabel
            anchors.left: parent.left
            anchors.leftMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            text: group.label.toUpperCase()
            font.family: T3Theme.fontUi
            font.pixelSize: Theme.fontMicro
            font.weight: Theme.weightSemibold
            font.letterSpacing: 1
            color: group.tint
        }

        Text {
            id: groupCount
            anchors.left: groupLabel.right
            anchors.leftMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            text: group.count
            font.family: T3Theme.fontUi
            font.pixelSize: Theme.fontMicro
            font.weight: Theme.weightMedium
            font.features: T3Theme.tabularNumberFeatures
            color: T3Theme.textFaint
        }

        Rectangle {
            anchors.left: groupCount.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: group.rule
        }
    }

    component TabButton: Rectangle {
        id: tab

        property string label: ""
        property string pageName: ""
        readonly property bool selected: root.page === pageName

        width: tabText.implicitWidth + 20
        height: Theme.chipHeight
        radius: T3Theme.controlRadius
        color: selected ? T3Theme.hoverStrong
            : tabMouse.containsMouse || activeFocus ? T3Theme.hover : "transparent"
        border.width: activeFocus ? 1 : 0
        border.color: T3Theme.focus
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
            font.family: T3Theme.fontUi
            font.pixelSize: Theme.fontSecondary
            font.weight: tab.selected ? Theme.weightSemibold : Theme.weightRegular
            color: tab.selected ? T3Theme.textPrimary : T3Theme.textMuted
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
        readonly property bool quiet: row.lifecycle === "settled"
        readonly property bool flagged: !quiet && (row.tone === "red" || row.tone === "amber")
        readonly property bool actionsRevealed: inboxHover.hovered || activeFocus
            || settleAction.activeFocus
        readonly property color statusColor: root.toneColor(row.tone)

        width: parent ? parent.width : 0
        height: quiet ? T3Theme.quietRowHeight : T3Theme.activeRowHeight
        radius: T3Theme.rowRadius
        color: flagged ? root.toneFill(row.tone)
            : quiet ? "transparent" : T3Theme.surface
        border.width: activeFocus || flagged || !quiet ? 1 : 0
        border.color: activeFocus ? T3Theme.focus
            : flagged ? statusColor : T3Theme.border
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
            anchors.fill: parent
            radius: parent.radius
            color: inboxHover.hovered ? T3Theme.hoverStrong : "transparent"

            Behavior on color {
                ColorAnimation { duration: T3Theme.fastDuration }
            }
        }

        Item {
            id: inboxGlyph
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: inboxCard.quiet ? 14 : 18
            height: width

            Sym {
                anchors.centerIn: parent
                name: root.inboxIcon(inboxCard.row)
                size: inboxCard.quiet ? Theme.iconSmall : Theme.iconMedium
                symWeight: 450
                color: inboxCard.quiet ? T3Theme.textFaint : inboxCard.statusColor
            }

            Rectangle {
                visible: inboxCard.row.unread || inboxCard.row.active
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: -2
                width: 8
                height: 8
                radius: 4
                color: inboxCard.quiet ? T3Theme.canvas : inboxCard.color

                Rectangle {
                    anchors.centerIn: parent
                    width: 5
                    height: 5
                    radius: 3
                    color: inboxCard.statusColor
                }
            }
        }

        Item {
            id: inboxSide
            readonly property bool showingAction: inboxCard.actionsRevealed
                && inboxCard.row.canSettle

            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.top: parent.top
            // Passive state belongs to the title line. The taller inline
            // action still centres in the full card when it replaces status.
            anchors.topMargin: showingAction
                ? (inboxCard.height - settleAction.height) / 2 : 7
            width: showingAction ? settleAction.width : statusPill.width
            height: Math.max(statusPill.height, settleAction.height)

            Row {
                id: statusPill
                visible: !inboxCard.actionsRevealed || !inboxCard.row.canSettle
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Sym {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.inboxStatusIcon(inboxCard.row)
                    size: Theme.iconTiny
                    symWeight: 500
                    color: inboxCard.statusColor
                }

                Text {
                    id: statusLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.inboxStatus(inboxCard.row)
                    font.family: T3Theme.fontUi
                    font.pixelSize: Theme.fontCaption
                    font.weight: Theme.weightMedium
                    color: inboxCard.statusColor
                }
            }

            Action {
                id: settleAction
                visible: inboxCard.row.canSettle && inboxCard.actionsRevealed
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: inboxCard.row.lifecycle === "settled" ? "Unsettle" : "Settle"
                tint: T3Theme.accent
                fill: T3Theme.accentSoft
                hPadding: 14
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
            anchors.left: inboxGlyph.right
            anchors.leftMargin: 10
            anchors.right: inboxSide.left
            anchors.rightMargin: 8
            y: inboxCard.quiet ? 10 : 8
            text: inboxCard.row.title
            font.family: T3Theme.fontUi
            font.pixelSize: Theme.fontBody
            font.weight: inboxCard.row.unread || inboxCard.row.active
                ? Theme.weightSemibold : Theme.weightMedium
            color: inboxCard.quiet ? T3Theme.textSecondary : T3Theme.textPrimary
            elide: Text.ElideRight
        }

        Text {
            visible: !inboxCard.quiet
            anchors.left: inboxGlyph.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 9
            y: 31
            text: {
                const meta = root.inboxMeta(inboxCard.row);
                return inboxCard.row.detail !== "" && meta !== ""
                    ? inboxCard.row.detail + " · " + meta
                    : inboxCard.row.detail || meta;
            }
            font.family: T3Theme.fontUi
            font.pixelSize: Theme.fontSecondary
            color: inboxCard.row.tone === "red" ? T3Theme.red : T3Theme.textFaint
            elide: Text.ElideRight
        }
    }

    // ---- header -----------------------------------------------------------
    // Copy over the panel, closed by a hairline. This popover shares T3's
    // type and metrics, so it shares the rule that replaced their cards: a
    // branded wash behind a title is the loudest thing a 460px panel can do.
    Item {
        id: moduleHeader
        width: parent.width
        height: root.headerHeight

        Rectangle {
            x: -root.padding
            y: parent.height - 1
            width: root.width
            height: 1
            color: T3Theme.border
        }

        Item {
            id: topLevelHeader
            visible: root.page !== "commits"
            anchors.fill: parent

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 11
                anchors.right: topTabs.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Row {
                    spacing: 7

                    BrandIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.iconMedium
                        height: Theme.iconMedium
                        name: "github"
                        colorized: true
                        tint: T3Theme.textPrimary
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "GitHub"
                        font.family: T3Theme.fontUi
                        font.pixelSize: Theme.fontBody
                        font.weight: Theme.weightSemibold
                        font.letterSpacing: -0.2
                        color: T3Theme.textPrimary
                    }

                    Rectangle {
                        visible: GitHub.pendingInboxCount > 0 && moduleHeader.width >= 420
                        anchors.verticalCenter: parent.verticalCenter
                        width: pendingText.implicitWidth + 10
                        height: 18
                        radius: 5
                        color: root.toneFill(GitHub.badgeTone)

                        Text {
                            id: pendingText
                            anchors.centerIn: parent
                            text: GitHub.pendingInboxCount + " pending"
                            font.family: T3Theme.fontUi
                            font.pixelSize: Theme.fontMicro
                            font.weight: Theme.weightMedium
                            font.features: T3Theme.tabularNumberFeatures
                            color: root.toneColor(GitHub.badgeTone)
                        }
                    }
                }

                Row {
                    spacing: 6

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 5
                        height: 5
                        radius: 3
                        color: GitHub.inboxError !== "" || GitHub.error !== ""
                            ? T3Theme.red : GitHub.polling || GitHub.inboxPolling
                                ? T3Theme.amber : T3Theme.success
                    }

                    Text {
                        width: Math.max(0, topTabs.x - 40)
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: {
                            const busy = root.page === "inbox"
                                ? GitHub.inboxPolling : GitHub.polling;
                            const checked = root.page === "inbox"
                                ? GitHub.inboxCheckedAt : GitHub.checkedAt;
                            if (busy)
                                return "Checking activity…";
                            if (GitHub.inboxError !== "")
                                return "Inbox paused · cached activity shown";
                            if (GitHub.error !== "" && root.page === "repos")
                                return "Repository feed unavailable";
                            const account = GitHub.login !== "" ? "@" + GitHub.login : "GitHub CLI";
                            const age = checked > 0 ? Helpers.agoLabel(checked, root.now) : "not checked";
                            return account + " · " + age;
                        }
                        font.family: T3Theme.fontUi
                        font.pixelSize: Theme.fontCaption
                        color: T3Theme.textFaint
                    }
                }
            }

            Row {
                id: topTabs
                anchors.right: refreshButton.left
                anchors.rightMargin: 3
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
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: T3Theme.iconButtonSize
                height: T3Theme.iconButtonSize
                radius: T3Theme.controlRadius
                color: refreshMouse.containsMouse || activeFocus
                    ? T3Theme.hoverStrong : "transparent"
                border.width: activeFocus ? 1 : 0
                border.color: T3Theme.focus
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
                    name: "refresh"
                    size: Theme.iconMedium
                    symWeight: 450
                    color: GitHub.polling || GitHub.inboxPolling
                        ? T3Theme.accent : T3Theme.textMuted
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
        }

        // Commit list: back, the repository, and a way out to the browser.
        IconButton {
            id: backAction
            visible: root.page === "commits"
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            symbol: "arrow_back"
            accessibleName: "Back to repositories"
            tint: T3Theme.textMuted
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
        IconButton {
            id: copyRepoLink

            readonly property string url: GitHub.repoUrl(root.selectedSlug)
            readonly property bool confirmed: root.copied !== "" && root.copied === url

            visible: root.page === "commits"
            anchors.right: openRepoLink.left
            anchors.rightMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            symbol: confirmed ? "check" : "content_copy"
            accessibleName: confirmed ? "Repository URL copied" : "Copy repository URL"
            tint: confirmed ? T3Theme.accent : T3Theme.textMuted
            onTriggered: root.copy(copyRepoLink.url)
        }

        IconButton {
            id: openRepoLink
            visible: root.page === "commits"
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            symbol: "open_in_new"
            accessibleName: "Open repository on GitHub"
            tint: T3Theme.accent
            onTriggered: {
                GitHub.open(GitHub.repoUrl(root.selectedSlug));
                Popouts.close();
            }
        }
    }

    // ---- body -------------------------------------------------------------
    Item {
        width: parent.width
        height: Math.min(body.contentHeight, root.maxBodyHeight)

        Flickable {
            id: body

            anchors.fill: parent
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

        ScrollChrome {
            anchors.fill: parent
            target: body
            edgeColor: T3Theme.canvas
            thumbColor: T3Theme.accent
        }
    }

    // ---- footer -----------------------------------------------------------
    Item {
        width: parent.width
        height: root.footerHeight

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: T3Theme.border
        }

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            width: 5
            height: 5
            radius: 3
            color: GitHub.inboxError !== "" || GitHub.error !== ""
                ? T3Theme.red : T3Theme.success
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 19
            anchors.right: footerSummary.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            text: {
                if (root.page === "commits") {
                    const branch = root.selectedRepo ? root.selectedRepo.branch : "";
                    return branch || "Default branch";
                }
                return GitHub.login !== "" ? "@" + GitHub.login : "GitHub CLI";
            }
            elide: Text.ElideRight
            font.family: T3Theme.fontUi
            font.pixelSize: Theme.fontCaption
            color: T3Theme.textFaint
        }

        Text {
            id: footerSummary
            anchors.right: parent.right
            anchors.rightMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            text: {
                if (root.page === "commits")
                    return root.commitRows.length + " latest commits";
                if (root.page === "repos")
                    return root.visibleRepos.length + " repositories";
                return GitHub.runningCount + " active"
                    + (GitHub.pendingInboxCount > 0
                        ? " · " + GitHub.pendingInboxCount + " pending" : "");
            }
            font.family: T3Theme.fontUi
            font.pixelSize: Theme.fontCaption
            font.features: T3Theme.tabularNumberFeatures
            color: T3Theme.textFaint
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
            spacing: 4

            Empty {
                visible: GitHub.inboxError !== ""
                text: "Inbox temporarily paused\n" + GitHub.inboxError
                color: T3Theme.red
            }

            Empty {
                visible: GitHub.notificationError !== ""
                text: "Notifications unavailable · " + GitHub.notificationError
                color: T3Theme.amber
            }

            Empty {
                visible: inboxList.failedWorkflows.length > 0
                text: "Workflows unavailable for " + inboxList.failedWorkflows.length
                    + (inboxList.failedWorkflows.length === 1 ? " repository · "
                        : " repositories · ")
                    + inboxList.failedWorkflows.slice(0, 3).join(", ")
                color: T3Theme.amber
            }

            Empty {
                visible: inboxList.failedEvents.length > 0
                text: "Repository events unavailable for " + inboxList.failedEvents.length
                    + (inboxList.failedEvents.length === 1 ? " repository · "
                        : " repositories · ")
                    + inboxList.failedEvents.slice(0, 3).join(", ")
                color: T3Theme.amber
            }

            GitHubStatus {
                shown: !GitHub.inboxReady && root.inboxRows.length === 0
                    && GitHub.inboxError === ""
                width: parent.width
                kind: "loading"
                title: GitHub.ciReportsEnabled
                    ? "Loading workflows, notifications, and repository updates…"
                    : "Loading notifications and repository updates…"
            }

            GitHubStatus {
                shown: GitHub.inboxReady && root.inboxRows.length === 0
                    && GitHub.inboxError === "" && GitHub.notificationError === ""
                width: parent.width
                glyph: "inbox"
                title: "Inbox is clear"
                detail: GitHub.ciReportsEnabled ? ""
                    : "Workflow reports are disabled in settings"
            }

            Rectangle {
                id: settleAllBar
                visible: GitHub.pendingInboxCount > 0
                width: parent.width
                height: visible ? 40 : 0
                radius: T3Theme.controlRadius
                color: T3Theme.surface
                border.width: 1
                border.color: T3Theme.border

                Sym {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    name: "done_all"
                    size: Theme.iconSmall
                    symWeight: 450
                    color: T3Theme.accent
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 32
                    anchors.right: settleAllAction.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: GitHub.pendingInboxCount
                        + (GitHub.pendingInboxCount === 1 ? " item to review" : " items to review")
                    elide: Text.ElideRight
                    font.family: T3Theme.fontUi
                    font.pixelSize: Theme.fontSecondary
                    color: T3Theme.textFaint
                }

                Action {
                    id: settleAllAction
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Settle all"
                    hPadding: 16
                    tint: T3Theme.accent
                    fill: T3Theme.accentSubtle
                    onTriggered: GitHub.settleAllInboxItems()
                }
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
                    spacing: 4

                    GroupHeader {
                        visible: inboxSection.modelData.id !== "settled"
                        width: parent.width
                        label: inboxSection.modelData.id === "active" ? "Working"
                            : inboxSection.modelData.id === "attention" ? "Needs you"
                            : inboxSection.modelData.title
                        count: inboxSection.modelData.rows.length
                        tint: inboxSection.modelData.id === "attention" ? T3Theme.amber
                            : inboxSection.modelData.id === "active" ? T3Theme.accent
                            : T3Theme.textMuted
                        rule: inboxSection.modelData.id === "attention" ? T3Theme.amberBorder
                            : inboxSection.modelData.id === "active" ? T3Theme.accentSoft
                            : T3Theme.border
                    }

                    Rectangle {
                        id: settledDrawer
                        visible: inboxSection.modelData.id === "settled"
                        width: parent.width
                        height: visible ? 36 : 0
                        radius: T3Theme.controlRadius
                        color: settledMouse.containsMouse || activeFocus
                            ? T3Theme.hoverStrong : "transparent"
                        border.width: activeFocus ? 1 : 0
                        border.color: T3Theme.focus
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

                        // Anchored to the label rather than to a measured
                        // lane: the count used to sit at a fixed 62px, which
                        // only cleared "Settled" while the panel was set in a
                        // proportional face. It follows the word now.
                        Text {
                            id: settledLabel
                            anchors.left: parent.left
                            anchors.leftMargin: 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Settled".toUpperCase()
                            font.family: T3Theme.fontUi
                            font.pixelSize: Theme.fontMicro
                            font.weight: Theme.weightSemibold
                            font.letterSpacing: 1
                            color: T3Theme.textFaint
                        }

                        Text {
                            id: settledCount
                            anchors.left: settledLabel.right
                            anchors.leftMargin: 7
                            anchors.verticalCenter: parent.verticalCenter
                            text: inboxSection.modelData.rows.length
                            font.family: T3Theme.fontUi
                            font.pixelSize: Theme.fontMicro
                            font.weight: Theme.weightMedium
                            font.features: T3Theme.tabularNumberFeatures
                            color: T3Theme.textFaint
                        }

                        Rectangle {
                            anchors.left: settledCount.right
                            anchors.leftMargin: 10
                            anchors.right: settledChevron.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            height: 1
                            color: T3Theme.border
                        }

                        Sym {
                            id: settledChevron
                            anchors.right: parent.right
                            anchors.rightMargin: 2
                            anchors.verticalCenter: parent.verticalCenter
                            name: root.settledExpanded ? "expand_less" : "expand_more"
                            size: Theme.iconSmall
                            symWeight: 450
                            color: T3Theme.textFaint
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
            spacing: 4

            Rectangle {
                id: repoSearchBox
                visible: root.visibleRepos.length > 6 || root.repoSearchText !== ""
                width: parent.width
                height: 36
                radius: T3Theme.controlRadius
                color: T3Theme.surface
                border.width: repoSearchInput.activeFocus ? 1 : 0
                border.color: T3Theme.focus

                Sym {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: Theme.iconSmall
                    symWeight: 450
                    color: T3Theme.textFaint
                }

                TextInput {
                    id: repoSearchInput
                    anchors.left: parent.left
                    anchors.leftMargin: 32
                    anchors.right: clearRepoSearch.visible ? clearRepoSearch.left : parent.right
                    anchors.rightMargin: clearRepoSearch.visible ? 4 : 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.repoSearchText
                    onTextEdited: root.repoSearchText = text
                    clip: true
                    selectByMouse: true
                    font.family: T3Theme.fontUi
                    font.pixelSize: Theme.fontSecondary
                    color: T3Theme.textPrimary

                    Text {
                        visible: repoSearchInput.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search repositories"
                        font.family: T3Theme.fontUi
                        font.pixelSize: Theme.fontSecondary
                        color: T3Theme.textFaint
                    }
                }

                IconButton {
                    id: clearRepoSearch
                    visible: repoSearchInput.text !== ""
                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    controlSize: 26
                    symbol: "close"
                    accessibleName: "Clear repository search"
                    tint: T3Theme.textFaint
                    onTriggered: {
                        root.repoSearchText = "";
                        repoSearchInput.text = "";
                        repoSearchInput.forceActiveFocus();
                    }
                }
            }

            Empty {
                visible: GitHub.error !== ""
                text: "GitHub unavailable\n" + GitHub.error
                color: T3Theme.red
            }

            Empty {
                visible: Object.keys(GitHub.watchErrors).length > 0
                text: Object.keys(GitHub.watchErrors).length === 1
                    ? "1 watched repository is unavailable · "
                        + Object.keys(GitHub.watchErrors)[0]
                    : Object.keys(GitHub.watchErrors).length
                        + " watched repositories are unavailable"
                color: T3Theme.amber
            }

            GitHubStatus {
                shown: GitHub.error === "" && !GitHub.ready
                width: parent.width
                kind: "loading"
                title: "Loading repositories…"
            }

            GitHubStatus {
                shown: GitHub.error === "" && GitHub.ready && GitHub.repos.length === 0
                width: parent.width
                glyph: "folder_open"
                title: "No repositories this account can see"
            }

            Text {
                visible: root.repoSearchText !== "" && root.filteredRepos.length === 0
                width: parent.width
                topPadding: 24
                bottomPadding: 24
                text: "No repositories match “" + root.repoSearchText + "”"
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.family: T3Theme.fontUi
                font.pixelSize: Theme.fontSecondary
                color: T3Theme.textFaint
            }

            GroupHeader {
                visible: root.filteredRepos.length > 0
                label: "Repositories"
                count: root.filteredRepos.length
            }

            Repeater {
                model: root.filteredRepos

                delegate: Rectangle {
                    id: repoRow

                    required property var modelData
                    required property int index

                    readonly property bool unread: modelData.pushedAt !== ""
                        && GitHub.seenAt !== "" && modelData.pushedAt > GitHub.seenAt

                    width: repoList.width
                    height: T3Theme.activeRowHeight
                    radius: T3Theme.rowRadius
                    color: T3Theme.surface
                    border.width: 1
                    border.color: activeFocus ? T3Theme.focus : T3Theme.border
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

                    HoverHandler { id: repoHover }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            repoRow.forceActiveFocus();
                            root.showCommits(repoRow.modelData.slug);
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: repoHover.hovered ? T3Theme.hoverStrong : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: T3Theme.fastDuration }
                        }
                    }

                    Item {
                        id: repoGlyph
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18

                        Sym {
                            anchors.centerIn: parent
                            name: "folder"
                            size: Theme.iconMedium
                            symWeight: 450
                            color: repoRow.unread ? T3Theme.accent : T3Theme.textMuted
                        }

                        Rectangle {
                            visible: repoRow.unread
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: -2
                            width: 8
                            height: 8
                            radius: 4
                            color: repoRow.color

                            Rectangle {
                                anchors.centerIn: parent
                                width: 5
                                height: 5
                                radius: 3
                                color: T3Theme.accent
                            }
                        }
                    }

                    Row {
                        id: repoTail
                        anchors.right: parent.right
                        anchors.rightMargin: 9
                        y: 7
                        spacing: 7

                        Sym {
                            visible: GitHub.watchError(repoRow.modelData.slug) !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            name: "warning"
                            size: Theme.iconTiny
                            color: T3Theme.amber
                        }

                        Rectangle {
                            visible: repoRow.modelData.watched
                            anchors.verticalCenter: parent.verticalCenter
                            width: watchLabel.implicitWidth + 10
                            height: watchLabel.implicitHeight + 4
                            radius: 4
                            color: T3Theme.accentSubtle

                            Text {
                                id: watchLabel
                                anchors.centerIn: parent
                                text: "Watching"
                                font.family: T3Theme.fontUi
                                font.pixelSize: Theme.fontMicro
                                font.weight: Theme.weightMedium
                                color: T3Theme.accent
                            }
                        }

                        Sym {
                            visible: repoRow.modelData.isPrivate
                            anchors.verticalCenter: parent.verticalCenter
                            name: "lock"
                            size: Theme.iconTiny
                            color: T3Theme.textFaint
                        }

                        Sym {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "chevron_right"
                            size: Theme.iconSmall
                            color: T3Theme.textFaint
                        }
                    }

                    RepoName {
                        anchors.left: repoGlyph.right
                        anchors.leftMargin: 10
                        anchors.right: repoTail.left
                        anchors.rightMargin: 8
                        y: 5
                        height: 22
                        owner: repoRow.modelData.owner
                        name: repoRow.modelData.name
                        strong: repoRow.unread
                    }

                    Text {
                        anchors.left: repoGlyph.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        y: 31
                        text: {
                            const parts = [];
                            if (repoRow.modelData.branch)
                                parts.push(repoRow.modelData.branch);
                            const age = Helpers.relTime(repoRow.modelData.pushedAt, root.now);
                            if (age !== "")
                                parts.push("updated " + age + " ago");
                            return parts.join(" · ");
                        }
                        elide: Text.ElideRight
                        font.family: T3Theme.fontUi
                        font.pixelSize: Theme.fontSecondary
                        color: T3Theme.textFaint
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
            spacing: 4

            // What changed since you last looked, in the same terms the
            // repository row's dot used.
            GroupHeader {
                visible: root.commitRows.length > 0
                label: root.newCommitCount > 0 ? "New since last visit" : "Latest commits"
                count: root.newCommitCount > 0 ? root.newCommitCount : root.commitRows.length
                tint: root.newCommitCount > 0 ? T3Theme.accent : T3Theme.textMuted
                rule: root.newCommitCount > 0 ? T3Theme.accentSoft : T3Theme.border
            }

            Empty {
                visible: root.commitEntry !== null && root.commitEntry.error !== ""
                text: "Commits unavailable\n"
                    + (root.commitEntry ? root.commitEntry.error : "")
                color: T3Theme.red
            }

            GitHubStatus {
                shown: root.commitEntry === null
                    || (root.commitEntry.loading && root.commitRows.length === 0)
                width: parent.width
                kind: "loading"
                title: "Loading commits…"
            }

            GitHubStatus {
                shown: root.commitEntry !== null && !root.commitEntry.loading
                    && root.commitEntry.error === "" && root.commitRows.length === 0
                width: parent.width
                glyph: "commit"
                title: "No commits on this branch yet"
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
                    height: commitBand.height + (expanded ? expandedCard.height + 6
                        : T3Theme.activeRowHeight)

                    HDivider {
                        id: commitBand
                        visible: commitRow.bandBreak
                        height: visible ? root.dividerHeight : 0
                    }

                    // Collapsed: subject on one line, provenance under it.
                    Rectangle {
                        id: collapsed
                        visible: !commitRow.expanded
                        y: commitBand.height
                        width: parent.width
                        height: T3Theme.activeRowHeight
                        radius: T3Theme.rowRadius
                        color: collapsedMouse.containsMouse || activeFocus
                            ? T3Theme.hoverStrong : T3Theme.surface
                        border.width: 1
                        border.color: activeFocus ? T3Theme.focus : T3Theme.border
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

                        Item {
                            id: commitGlyph
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18
                            height: 18

                            Sym {
                                anchors.centerIn: parent
                                name: "commit"
                                size: Theme.iconMedium
                                symWeight: 450
                                color: commitRow.unread ? T3Theme.accent : T3Theme.textMuted
                            }

                            Rectangle {
                                visible: commitRow.unread
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: -2
                                width: 8
                                height: 8
                                radius: 4
                                color: collapsed.color

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 5
                                    height: 5
                                    radius: 3
                                    color: T3Theme.accent
                                }
                            }
                        }

                        Column {
                            anchors.left: commitGlyph.right
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                width: parent.width
                                text: commitRow.modelData.subject
                                font.family: T3Theme.fontUi
                                font.pixelSize: Theme.fontBody
                                font.weight: commitRow.unread
                                    ? Theme.weightMedium : Theme.weightRegular
                                color: commitRow.unread ? T3Theme.textPrimary
                                    : T3Theme.textSecondary
                                elide: Text.ElideRight
                            }

                            Row {
                                spacing: 0

                                Text {
                                    text: commitRow.modelData.short
                                    font.family: T3Theme.fontMono
                                    font.pixelSize: Theme.fontCaption
                                    color: T3Theme.textFaint
                                }

                                Text {
                                    text: " · " + commitRow.modelData.author + " · "
                                        + Helpers.agoLabelIso(commitRow.modelData.date, root.now)
                                    font.family: T3Theme.fontUi
                                    font.pixelSize: Theme.fontCaption
                                    color: T3Theme.textFaint
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
                        y: commitBand.height + 4
                        width: parent.width
                        height: cardBody.implicitHeight + 24
                        radius: T3Theme.rowRadius
                        color: T3Theme.surfaceRaised
                        border.width: 1
                        border.color: T3Theme.border

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
                                    font.family: T3Theme.fontUi
                                    font.pixelSize: Theme.fontBody
                                    font.weight: Theme.weightMedium
                                    color: T3Theme.textPrimary
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Text {
                                visible: commitRow.modelData.body !== ""
                                x: 17
                                width: parent.width - 17
                                topPadding: 7
                                text: commitRow.modelData.body
                                font.family: T3Theme.fontUi
                                font.pixelSize: Theme.fontSecondary
                                lineHeight: Theme.proseLineHeight
                                color: T3Theme.textMuted
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
                                        font.family: T3Theme.fontMono
                                        font.pixelSize: Theme.fontCaption
                                        color: T3Theme.textFaint
                                    }

                                    Text {
                                        visible: commitRow.stats !== null
                                        text: commitRow.stats
                                            ? commitRow.stats.files
                                                + (commitRow.stats.files === 1 ? " file" : " files")
                                            : ""
                                        font.family: T3Theme.fontUi
                                        font.pixelSize: Theme.fontCaption
                                        color: T3Theme.textFaint
                                    }

                                    Text {
                                        visible: commitRow.stats !== null
                                        text: commitRow.stats ? "+" + commitRow.stats.additions : ""
                                        font.family: T3Theme.fontMono
                                        font.pixelSize: Theme.fontCaption
                                        font.weight: Theme.weightMedium
                                        color: T3Theme.success
                                    }

                                    Text {
                                        visible: commitRow.stats !== null
                                        text: commitRow.stats ? "−" + commitRow.stats.deletions : ""
                                        font.family: T3Theme.fontMono
                                        font.pixelSize: Theme.fontCaption
                                        font.weight: Theme.weightMedium
                                        color: T3Theme.red
                                    }

                                    Text {
                                        visible: commitRow.stats === null
                                        text: "counting…"
                                        font.family: T3Theme.fontUi
                                        font.pixelSize: Theme.fontCaption
                                        color: T3Theme.textFaint
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
                                    font.family: T3Theme.fontUi
                                    font.pixelSize: Theme.fontCaption
                                    color: T3Theme.textFaint
                                }
                            }

                            Row {
                                x: 17
                                topPadding: 11
                                spacing: 6

                                Action {
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

                                Action {
                                    readonly property bool confirmed: root.copied !== ""
                                        && root.copied === commitRow.modelData.sha

                                    label: confirmed ? "Copied" : "Copy SHA"
                                    tint: confirmed ? T3Theme.accent : T3Theme.textMuted
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
