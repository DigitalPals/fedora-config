pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

// Responsive T3 Code mini-client. T3 owns the inner canvas and type system;
// the surrounding popout still supplies the shell shadow and opening motion.
Surface {
    id: root

    spacing: 6
    padding: T3Theme.pagePadding
    surfaceColor: T3Theme.canvas
    surfaceBorderColor: T3Theme.borderStrong

    availableWidth: 484 - Theme.barSideMargin * 2
    availableHeight: 800 - Theme.barTopMargin - Theme.barHeight - 16

    readonly property int pageMaxWidth: page === "inbox" ? 460 : 520
    implicitWidth: Math.max(Theme.t3MinWidth,
        Math.min(pageMaxWidth, root.availableWidth))

    readonly property int headerHeight: inboxHeader.visible ? inboxHeader.height : 0
    readonly property int footerHeight: footer.visible ? footer.height : 0
    readonly property int maxPageHeight: Math.max(300, root.availableHeight
        - root.padding * 2 - headerHeight
        - (inboxHeader.visible ? root.spacing : 0)
        - footerHeight - (footer.visible ? root.spacing : 0)
        - (noReadBanner.visible ? noReadBanner.height + root.spacing : 0))

    // A thread is the one page that would take every pixel the screen offers.
    // The inbox and the new-thread form end, so the budget above is a ceiling
    // they rarely touch; a transcript does not end, so uncapped it stretched
    // the panel down the whole output. The timeline already scrolls, so give
    // it half the room below the bar instead: transcript enough to read on a
    // tall screen, without a panel that reaches the bottom edge.
    //
    // The floor is what keeps a short output usable. Half is generous on a
    // 1440px screen and mean on a 900px one, where it would land under the
    // reading window a thread needs — so below roughly 1080px the thread
    // takes more than half rather than less, and maxPageHeight still has the
    // last word on the smallest outputs.
    readonly property int threadMaxHeight: Math.min(root.maxPageHeight,
        Math.max(520, Math.round(root.availableHeight / 2)))
    readonly property T3NewThreadPage loadedNewThreadPage: root.page === "new"
        ? pageLoader.item as T3NewThreadPage : null

    detachedOverflowHeight: loadedNewThreadPage
        ? loadedNewThreadPage.detachedOverflowHeight : 0
    detachedOverflowItem: loadedNewThreadPage
        ? loadedNewThreadPage.detachedOverflowItem : null

    property string page: "inbox"
    property string selectedThreadId: ""
    property bool inboxSnoozedExpanded: false
    property bool inboxSettledExpanded: false
    property bool connectionMenuOpen: false

    function showInbox() {
        connectionMenuOpen = false;
        T3Code.forgetThread(selectedThreadId);
        page = "inbox";
        T3Code.closeDetail();
    }

    function showThread(threadId) {
        if (typeof threadId !== "string" || threadId === "")
            return;
        connectionMenuOpen = false;
        selectedThreadId = threadId;
        T3Code.rememberThread(threadId);
        page = "thread";
    }

    function restoreThread() {
        if (page !== "inbox")
            return;
        const threadId = T3Code.restorableThreadId();
        if (threadId !== "")
            showThread(threadId);
    }

    function showNew() {
        connectionMenuOpen = false;
        T3Code.ensureNewThreadDraft(selectedThreadId);
        page = "new";
        T3Code.closeDetail();
    }

    function showPlanInNewThread(plan) {
        if (T3Code.prepareNewThreadForPlan(selectedThreadId, plan)) {
            connectionMenuOpen = false;
            page = "new";
            T3Code.closeDetail();
        }
    }

    function handleEscape(): bool {
        if (connectionMenuOpen) {
            connectionMenuOpen = false;
            return true;
        }
        if (page === "inbox")
            return false;
        showInbox();
        return true;
    }

    function containsConnectionMenuPoint(item, x, y) {
        const inMenu = connectionMenu.mapFromItem(item, x, y);
        const inButton = connectionMenuButton.mapFromItem(item, x, y);
        return inMenu.x >= 0 && inMenu.x <= connectionMenu.width
                && inMenu.y >= 0 && inMenu.y <= connectionMenu.height
            || inButton.x >= 0 && inButton.x <= connectionMenuButton.width
                && inButton.y >= 0 && inButton.y <= connectionMenuButton.height;
    }

    TapHandler {
        enabled: root.connectionMenuOpen
        margin: root.Window.window
            ? Math.max(root.Window.window.width, root.Window.window.height) : 0
        onTapped: eventPoint => {
            if (!root.containsConnectionMenuPoint(root,
                    eventPoint.position.x, eventPoint.position.y))
                root.connectionMenuOpen = false;
        }
    }

    Component {
        id: inboxPage

        T3InboxPage {
            width: root.width - root.padding * 2
            maxHeight: root.maxPageHeight
            snoozedExpanded: root.inboxSnoozedExpanded
            settledExpanded: root.inboxSettledExpanded
            onSnoozedExpandedChanged: root.inboxSnoozedExpanded = snoozedExpanded
            onSettledExpandedChanged: root.inboxSettledExpanded = settledExpanded
            onThreadRequested: threadId => root.showThread(threadId)
        }
    }

    Component {
        id: threadPage

        T3ThreadPage {
            width: root.width - root.padding * 2
            maxHeight: root.threadMaxHeight
            threadId: root.selectedThreadId
            onBackRequested: root.showInbox()
            onNewPlanRequested: plan => root.showPlanInNewThread(plan)
        }
    }

    Component {
        id: newPage

        T3NewThreadPage {
            width: root.width - root.padding * 2
            maxHeight: root.maxPageHeight
            contextThreadId: root.selectedThreadId
            onBackRequested: root.showInbox()
        }
    }

    // The header is a block of copy over the panel, closed by a hairline —
    // not a card sitting on one. The branded wash went with the card: an
    // accent field behind a title is the loudest thing a 460px panel can do,
    // and the menubar earns its identity from the marks inside it instead.
    Item {
        id: inboxHeader
        visible: root.page === "inbox"
        z: 100
        width: parent.width
        height: T3Theme.headerHeight

        Rectangle {
            x: -root.padding
            y: parent.height - 1
            width: root.width
            height: 1
            color: T3Theme.border
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 2
            anchors.right: headerActions.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Row {
                spacing: 6

                BrandIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 11
                    name: "t3"
                    colorized: true
                    tint: T3Code.state === "connected"
                        ? T3Theme.textPrimary : T3Theme.textFaint
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Code"
                    font.family: T3Theme.fontUi
                    font.pixelSize: Theme.fontBody
                    font.weight: Theme.weightSemibold
                    font.letterSpacing: -0.25
                    color: T3Theme.textPrimary
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "·"
                    font.family: T3Theme.fontUi
                    font.pixelSize: Theme.fontMicro
                    color: Theme.dotDim
                }

                Text {
                    id: nightlyText
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Nightly"
                    font.family: T3Theme.fontUi
                    font.pixelSize: Theme.fontMicro
                    color: T3Theme.textFaint
                }
            }

            Row {
                spacing: 6

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 5
                    height: 5
                    radius: 3
                    color: T3Code.state === "connected" ? T3Theme.success
                        : T3Code.state === "connecting" ? T3Theme.amber : T3Theme.red
                }

                Text {
                    width: Math.max(0, inboxHeader.width - headerActions.width - 30)
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: {
                        if (T3Code.cloudLoginRunning)
                            return "Finish signing in in your browser";
                        if (T3Code.state === "signed-out" || T3Code.state === "cloud-empty")
                            return "T3 Connect";
                        if (T3Code.state !== "connected")
                            return T3Code.connectionError !== "" ? T3Code.connectionError
                                : T3Code.state === "connecting" ? "Connecting…" : "Unavailable";
                        return (T3Code.environmentLabel || "Connected")
                            + (T3Code.readOnly ? " · read-only" : "");
                    }
                    font.family: T3Theme.fontUi
                    font.pixelSize: Theme.fontCaption
                    color: T3Code.readOnly ? T3Theme.amber : T3Theme.textFaint
                }
            }
        }

        Row {
            id: headerActions
            anchors.right: parent.right
            anchors.rightMargin: 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            IconButton {
                id: newButton
                visible: T3Code.paired
                readonly property bool usable: T3Code.canDispatch && T3Code.hasReadyProvider
                    && T3Code.hasProjects
                enabled: usable
                symbol: "edit_square"
                accessibleName: "New thread"
                tint: usable ? T3Theme.accent : T3Theme.textFaint
                onTriggered: root.showNew()
            }

            IconButton {
                id: connectionMenuButton
                visible: T3Code.paired
                symbol: "more_horiz"
                accessibleName: "Connection menu"
                tint: root.connectionMenuOpen ? T3Theme.accent : T3Theme.textMuted
                onTriggered: root.connectionMenuOpen = !root.connectionMenuOpen
            }
        }

        Rectangle {
            id: connectionMenu
            visible: root.connectionMenuOpen
            z: 1000
            anchors.right: parent.right
            anchors.rightMargin: 0
            y: parent.height + 4
            width: Math.min(250, inboxHeader.width - 8)
            height: connectionMenuColumn.implicitHeight + 12
            radius: T3Theme.panelRadius
            color: T3Theme.overlay
            border.width: 1
            border.color: T3Theme.borderStrong

            Column {
                id: connectionMenuColumn
                x: 6
                y: 6
                width: parent.width - 12
                spacing: 2

                Text {
                    width: parent.width
                    leftPadding: 8
                    rightPadding: 8
                    topPadding: 6
                    bottomPadding: 4
                    text: T3Code.environmentLabel || "T3 Code Nightly"
                    elide: Text.ElideRight
                    font.family: T3Theme.fontUi
                    font.pixelSize: Theme.fontSecondary
                    font.weight: Theme.weightSemibold
                    color: T3Theme.textPrimary
                }

                Text {
                    visible: T3Code.host !== ""
                    width: parent.width
                    leftPadding: 8
                    rightPadding: 8
                    bottomPadding: 6
                    text: T3Code.host.replace(/^https?:\/\//, "")
                    elide: Text.ElideMiddle
                    font.family: T3Theme.fontMono
                    font.pixelSize: Theme.fontMicro
                    color: T3Theme.textFaint
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: T3Theme.border
                }

                Rectangle {
                    width: parent.width
                    height: 36
                    radius: T3Theme.controlRadius
                    color: reconnectMouse.containsMouse ? T3Theme.hoverStrong : "transparent"
                    activeFocusOnTab: visible
                    Accessible.role: Accessible.Button
                    Accessible.name: "Reconnect"
                    Accessible.onPressAction: T3Code.connect()

                    Sym {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        name: "refresh"
                        size: Theme.iconSmall
                        color: T3Theme.textMuted
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 30
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Reconnect"
                        font.family: T3Theme.fontUi
                        font.pixelSize: Theme.fontSecondary
                        color: T3Theme.textSecondary
                    }

                    MouseArea {
                        id: reconnectMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.connectionMenuOpen = false;
                            T3Code.connect();
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: noReadBanner
        visible: T3Code.scopeMetadataKnown && !T3Code.canRead
        width: parent.width
        height: noReadText.implicitHeight + 12
        radius: T3Theme.controlRadius
        color: T3Theme.redSoft
        border.width: 1
        border.color: T3Theme.redBorder

        Text {
            id: noReadText
            x: 6
            y: 6
            width: parent.width - 12
            text: "This credential does not grant orchestration read access."
            wrapMode: Text.WordWrap
            lineHeight: Theme.proseLineHeight
            font.family: T3Theme.fontUi
            font.pixelSize: Theme.fontCaption
            color: T3Theme.red
        }
    }

    Loader {
        id: pageLoader
        width: parent.width
        sourceComponent: root.page === "thread" ? threadPage
            : root.page === "new" ? newPage : inboxPage
        height: item ? item.implicitHeight : 0
    }

    Item {
        id: footer
        visible: T3Code.state === "connected" && root.page === "inbox"
        width: parent.width
        height: T3Theme.footerHeight

        Rectangle {
            x: -root.padding
            anchors.top: parent.top
            width: root.width
            height: 1
            color: T3Theme.border
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            spacing: 6

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 5
                height: 5
                radius: 3
                color: T3Theme.success
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: T3Code.environmentLabel || "Connected"
                font.family: T3Theme.fontUi
                font.pixelSize: Theme.fontMicro
                color: T3Theme.textFaint
            }
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            text: T3Code.runningCount + " active"
                + (T3Code.attentionCount > 0 ? " · " + T3Code.attentionCount + " waiting" : "")
            font.family: T3Theme.fontUi
            font.pixelSize: Theme.fontMicro
            font.features: T3Theme.tabularNumberFeatures
            color: T3Theme.textFaint
        }
    }

    Connections {
        target: T3Code

        function onSettledThreadsChanged() {
            if (root.page === "thread" && T3Code.settledThreads.some(thread =>
                    thread.id === root.selectedThreadId)) {
                root.inboxSettledExpanded = true;
                root.showInbox();
            }
        }

        function onSnoozedThreadsChanged() {
            if (root.page === "thread" && T3Code.snoozedThreads.some(thread =>
                    thread.id === root.selectedThreadId)) {
                root.inboxSnoozedExpanded = true;
                root.showInbox();
            }
        }

        function onNewThreadConfirmed(threadId) {
            root.showThread(threadId);
        }

        function onStateChanged() {
            if (T3Code.state === "connected" && root.page === "thread"
                    && root.selectedThreadId !== "")
                T3Code.openDetail(root.selectedThreadId);
        }

        function onShellReadyChanged() {
            if (T3Code.shellReady)
                root.restoreThread();
        }
    }

    Component.onCompleted: root.restoreThread()
    Component.onDestruction: T3Code.closeDetail()
}
