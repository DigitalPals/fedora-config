pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../Common"

// Responsive three-page T3 mini-client. This Loader is recreated whenever
// the dropdown opens, so navigation always begins at Inbox; all drafts live
// in the T3Code singleton and therefore survive that teardown.
Surface {
    id: root

    spacing: 6

    // The host (Bar/IslandPopout) hands us the usable envelope of the output
    // it is drawn on — it has already taken off the side margins, the bar and
    // a shadow budget, so nothing here subtracts them a second time. Reading
    // Screens.focused instead would size against the wrong monitor whenever
    // the bar is pinned to one. The defaults stand in for a host that sets
    // neither, and reproduce the old 484x800 fallback.
    property real availableWidth: 484 - Theme.barSideMargin * 2
    property real availableHeight: 800 - Theme.barTopMargin - Theme.barHeight - 16

    implicitWidth: Math.max(Theme.t3MinWidth,
        Math.min(Theme.t3MaxWidth, root.availableWidth))

    readonly property int headerHeight: Theme.rowHeight
    readonly property int footerHeight: Theme.controlHeight
    readonly property int maxPageHeight: Math.max(300, root.availableHeight
        - root.padding * 2 - headerHeight - footerHeight - root.spacing * 2
        - (noReadBanner.visible ? noReadBanner.height + root.spacing : 0))

    property string page: "inbox"
    property string selectedThreadId: ""
    property bool inboxSnoozedExpanded: false
    property bool inboxSettledExpanded: false

    function showInbox() {
        page = "inbox";
        T3Code.closeDetail();
    }

    function showThread(threadId) {
        if (typeof threadId !== "string" || threadId === "")
            return;
        selectedThreadId = threadId;
        page = "thread";
    }

    function showNew() {
        T3Code.ensureNewThreadDraft(selectedThreadId);
        page = "new";
        T3Code.closeDetail();
    }

    function showPlanInNewThread(plan) {
        if (T3Code.prepareNewThreadForPlan(selectedThreadId, plan)) {
            page = "new";
            T3Code.closeDetail();
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
            maxHeight: root.maxPageHeight
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

    Item {
        width: parent.width
        height: root.headerHeight

        Column {
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Row {
                spacing: 6

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 11
                    width: 18
                    sourceSize: Qt.size(36, 22)
                    fillMode: Image.PreserveAspectFit
                    source: Quickshell.shellDir + "/assets/"
                        + (T3Code.state === "connected" ? "t3.svg" : "t3-dim.svg")
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Code"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontBody
                    font.weight: Theme.weightBold
                    font.letterSpacing: -0.3
                    color: "#fafafa"
                }

                Text {
                    visible: root.page !== "inbox"
                    anchors.verticalCenter: parent.verticalCenter
                    text: "· " + (root.page === "thread" ? "Thread" : "New")
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textDim
                }
            }

            Text {
                text: {
                    if (T3Code.state !== "connected")
                        return T3Code.state === "connecting" ? "connecting…"
                            : T3Code.state === "unpaired" ? "not paired"
                            : "server unreachable — retrying";
                    const environment = T3Code.environmentLabel !== ""
                        ? T3Code.environmentLabel : "connected";
                    return environment + " · " + T3Code.runningCount + " running · "
                        + T3Code.attentionCount + " waiting"
                        + (T3Code.readOnly ? " · read-only" : "");
                }
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: T3Code.readOnly ? Theme.amber : Theme.textDim
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            // "＋ New" lives in the header (design 5a) so the inbox needs no
            // title band of its own.
            Rectangle {
                id: newButton
                visible: T3Code.paired && root.page !== "new"
                anchors.verticalCenter: parent.verticalCenter
                width: newText.implicitWidth + 22
                height: Theme.controlHeight
                radius: 7
                readonly property bool usable: T3Code.canDispatch && T3Code.hasReadyProvider
                    && T3Code.hasProjects
                color: newMouse.containsMouse && usable
                    ? Qt.lighter(Theme.accentBg, 1.2) : Theme.accentBg
                opacity: usable ? 1 : 0.4
                activeFocusOnTab: usable && visible
                border.width: activeFocus ? 1 : 0
                border.color: Theme.accent

                Keys.onPressed: event => {
                    if (!newButton.usable)
                        return;
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                            || event.key === Qt.Key_Space) {
                        root.showNew();
                        event.accepted = true;
                    }
                }

                Text {
                    id: newText
                    anchors.centerIn: parent
                    text: "＋ New"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontSecondary
                    font.weight: Theme.weightSemibold
                    color: Theme.accent
                }

                MouseArea {
                    id: newMouse
                    anchors.fill: parent
                    enabled: newButton.usable
                    hoverEnabled: true
                    onClicked: root.showNew()
                }
            }

            Rectangle {
                visible: T3Code.paired
                anchors.verticalCenter: parent.verticalCenter
                width: 27
                height: Theme.controlHeight
                radius: 6
                color: refreshMouse.containsMouse ? Theme.hoverFill : "transparent"
                activeFocusOnTab: true

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                            || event.key === Qt.Key_Space) {
                        T3Code.connect();
                        event.accepted = true;
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "↻"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontBody
                    color: refreshMouse.containsMouse ? Theme.textMid : Theme.textLow
                }

                MouseArea {
                    id: refreshMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: T3Code.connect()
                }
            }
        }
    }

    Rectangle {
        id: noReadBanner
        visible: T3Code.scopeMetadataKnown && !T3Code.canRead
        width: parent.width
        height: noReadText.implicitHeight + 12
        radius: 7
        color: Theme.redBgSoft
        border.width: 1
        border.color: Theme.redBorder

        Text {
            id: noReadText
            x: 6
            y: 6
            width: parent.width - 12
            text: "This pairing token does not grant orchestration read access."
            wrapMode: Text.WordWrap
            lineHeight: Theme.proseLineHeight
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: Theme.redText
        }
    }

    // Deliberately synchronous: this popover's implicit height is the page's
    // height, and the host animates its geometry (and resizes the layer
    // surface) from it. An incubating page measures as zero, which opens the
    // body in two stages and collapses it on every navigation — the exact
    // per-frame resize commit 3f9c1d2 removed. The page is built inside the
    // host's own asynchronous incubation either way, so nothing here lands on
    // the click frame.
    Loader {
        id: pageLoader
        width: parent.width
        sourceComponent: root.page === "thread" ? threadPage
            : root.page === "new" ? newPage : inboxPage
        height: item ? item.implicitHeight : 0
    }

    Item {
        width: parent.width
        height: root.footerHeight

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: Theme.hairlineSoft
        }

        Item {
            id: connectionMeta
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.right: openClient.left
            anchors.rightMargin: 10
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            Rectangle {
                id: connectedDot
                visible: T3Code.state === "connected"
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 2
                width: 5
                height: 5
                radius: 3
                color: Theme.connected
                opacity: 0.8
            }

            Text {
                anchors.left: connectedDot.visible ? connectedDot.right : parent.left
                anchors.leftMargin: connectedDot.visible ? 6 : 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 2
                text: {
                    const status = T3Code.state === "connected" ? "connected" : T3Code.state;
                    return status + (T3Code.host !== ""
                        ? " · " + T3Code.host.replace(/^https?:\/\//, "") : "");
                }
                elide: Text.ElideRight
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontCaption
                color: Theme.textDim
            }
        }

        Text {
            id: openClient
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 2
            text: "Open T3 Code"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.weightSemibold
            color: openMouse.containsMouse ? "#c8e2f4" : Theme.accent

            MouseArea {
                id: openMouse
                anchors.fill: parent
                anchors.margins: -3
                hoverEnabled: true
                onClicked: {
                    Quickshell.execDetached(["xdg-open", T3Code.host !== ""
                        ? T3Code.host : "https://app.t3.codes"]);
                    Popouts.close();
                }
            }
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
    }

    Component.onCompleted: root.page = "inbox"
    Component.onDestruction: T3Code.closeDetail()
}
