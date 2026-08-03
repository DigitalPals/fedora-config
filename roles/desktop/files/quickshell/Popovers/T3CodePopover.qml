import QtQuick
import Quickshell
import "../Common"

// Responsive three-page T3 mini-client. This Loader is recreated whenever
// the dropdown opens, so navigation always begins at Inbox; all drafts live
// in the T3Code singleton and therefore survive that teardown.
Surface {
    id: root

    spacing: 6
    implicitWidth: Math.max(280, Math.min(460,
        (Screens.focused ? Screens.focused.width : 484) - Theme.barSideMargin * 2))

    readonly property int screenHeight: Screens.focused ? Screens.focused.height : 800
    readonly property int maxPageHeight: Math.max(300, screenHeight - 155)

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
            onNewRequested: root.showNew()
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
        height: 39

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
                    font.family: Theme.fontSans
                    font.pixelSize: 14
                    font.weight: 700
                    font.letterSpacing: -0.3
                    color: "#fafafa"
                }

                Text {
                    visible: root.page !== "inbox"
                    anchors.verticalCenter: parent.verticalCenter
                    text: "· " + (root.page === "thread" ? "Thread" : "New")
                    font.family: Theme.fontSans
                    font.pixelSize: 10
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
                font.family: Theme.fontSans
                font.pixelSize: 9
                color: T3Code.readOnly ? Theme.amber : Theme.textDim
            }
        }

        Rectangle {
            visible: T3Code.paired
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 27
            height: 23
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
                font.family: Theme.fontSans
                font.pixelSize: 12
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

    Rectangle {
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
            font.family: Theme.fontSans
            font.pixelSize: 10
            color: Theme.redText
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
        width: parent.width
        height: 27

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: Theme.hairlineSoft
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.right: openClient.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 2
            text: {
                const status = T3Code.state === "connected" ? "connected" : T3Code.state;
                const version = T3Code.serverVersion !== "" ? " · v" + T3Code.serverVersion : "";
                return status + version + (T3Code.host !== ""
                    ? " · " + T3Code.host.replace(/^https?:\/\//, "") : "");
            }
            elide: Text.ElideRight
            font.family: Theme.fontMono
            font.pixelSize: 9
            color: Theme.textDim
        }

        Text {
            id: openClient
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 2
            text: "Open T3 Code"
            font.family: Theme.fontSans
            font.pixelSize: 10
            font.weight: 550
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
