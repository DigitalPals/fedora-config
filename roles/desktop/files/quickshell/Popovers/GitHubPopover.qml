pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/GitHubHelpers.js" as Helpers

// Two-page repository feed: the repositories you can see, newest push first,
// and one repository's commits. Escape backs out of the commit list before it
// dismisses the popout, the way the T3 client does.
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

    property string page: "repos"
    property string selectedSlug: ""
    property string expandedSha: ""

    // Every relative label on screen is derived from this rather than from
    // Date.now() at binding time, so they all age together and none of them
    // needs its own timer.
    property double now: Date.now()

    readonly property var visibleRepos: GitHub.repos.slice(0, GitHub.opts.repos)
    readonly property var selectedRepo: GitHub.repos.find(r => r.slug === root.selectedSlug)
        ?? null
    readonly property var commitEntry: GitHub.commitCache[root.selectedSlug] ?? null
    readonly property var commitRows: root.commitEntry ? root.commitEntry.rows : []
    readonly property int newCommitCount: Helpers.newCommits(root.commitRows, GitHub.seenAt)

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

    // Escape goes back to the repository list first; from the list the host
    // dismisses the popout as usual.
    function handleEscape(): bool {
        if (page === "repos")
            return false;
        showRepos();
        return true;
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

    // ---- header -----------------------------------------------------------
    Item {
        width: parent.width
        height: root.headerHeight

        // Repository list: the module's own title and when it last looked.
        Text {
            visible: root.page === "repos"
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "GitHub"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontBody
            font.weight: Theme.weightSemibold
            color: Theme.textHi
        }

        Text {
            visible: root.page === "repos"
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: {
                if (GitHub.polling)
                    return "checking…";
                if (GitHub.checkedAt <= 0)
                    return "";
                return "checked " + Helpers.agoLabel(GitHub.checkedAt, root.now);
            }
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontSecondary
            color: Theme.textDim
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

            Text {
                anchors.centerIn: parent
                // nf-fa-check / nf-fa-copy
                text: copyRepoLink.confirmed ? "\uf00c" : "\uf0c5"
                font.family: Theme.fontIcon
                font.pixelSize: Theme.iconSmall
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
            sourceComponent: root.page === "commits" ? commitsPage : reposPage
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
                if (GitHub.error !== "")
                    return "feed unavailable";
                return root.visibleRepos.length + " of " + GitHub.repos.length
                    + " repos · click a repo for commits";
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

                        Text {
                            visible: repoRow.modelData.isPrivate
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\uf023" // nf-fa-lock
                            font.family: Theme.fontIcon
                            font.pixelSize: Theme.iconSmall
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
    Component.onCompleted: root.showRepos()
}
