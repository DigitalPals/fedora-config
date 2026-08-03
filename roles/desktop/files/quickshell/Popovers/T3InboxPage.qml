import QtQuick
import Quickshell
import "../Common"

Column {
    id: root

    property int maxHeight: 560
    property bool snoozedExpanded: false
    property bool settledExpanded: false
    signal threadRequested(string threadId)

    readonly property var needsYou: T3Code.threads.filter(thread =>
        thread.cls === "attention" || thread.cls === "error")
    readonly property var readyPlans: T3Code.threads.filter(thread =>
        thread.planReady && thread.cls !== "attention" && thread.cls !== "error")
    readonly property var runningThreads: T3Code.threads.filter(thread =>
        thread.cls === "running" && !thread.planReady)
    readonly property var quietThreads: T3Code.threads.filter(thread =>
        (thread.cls === "done" || thread.cls === "idle") && !thread.planReady)

    spacing: 5

    component Action: Rectangle {
        id: action
        property string label: ""
        property color tint: Theme.textLow
        property color fill: Theme.hoverFill
        property bool revealed: true
        signal triggered()

        width: labelText.implicitWidth + 18
        height: 22
        radius: 6
        color: actionMouse.containsMouse && enabled ? Qt.lighter(fill, 1.2) : fill
        opacity: enabled ? 1 : 0.4
        activeFocusOnTab: enabled && visible && revealed
        border.width: activeFocus ? 1 : 0
        border.color: Theme.accent

        Keys.onPressed: event => {
            if (!action.enabled)
                return;
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                action.triggered();
                event.accepted = true;
            }
        }

        Text {
            id: labelText
            anchors.centerIn: parent
            text: action.label
            font.family: Theme.fontSans
            font.pixelSize: 10
            font.weight: 600
            color: action.tint
        }

        MouseArea {
            id: actionMouse
            anchors.fill: parent
            enabled: action.enabled
            hoverEnabled: true
            onClicked: action.triggered()
        }
    }

    component GroupHeader: Item {
        id: group
        property string label: ""
        property int count: 0
        property color tint: Theme.textLow

        width: parent ? parent.width : 0
        height: 22

        Text {
            id: groupLabel
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: group.label
            font.family: Theme.fontSans
            font.pixelSize: 10
            font.weight: 600
            font.letterSpacing: 0.9
            color: group.tint
        }

        Text {
            id: groupCount
            anchors.left: groupLabel.right
            anchors.leftMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            text: group.count
            font.family: Theme.fontMono
            font.pixelSize: 10
            font.weight: 500
            color: Theme.textDim
        }

        Rectangle {
            anchors.left: groupCount.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: Theme.hairlineSoft
        }
    }

    component ThreadRow: Column {
        id: entry
        required property var thread

        readonly property bool active: thread.lifecycle === "active"
        readonly property bool settled: thread.lifecycle === "settled"
        readonly property bool snoozed: thread.lifecycle === "snoozed"
        readonly property bool quiet: settled || snoozed
            || thread.cls === "done" || thread.cls === "idle"
        // Actions replace the status word on hover; keyboard focus on the row
        // or an action keeps them revealed so tab users are not locked out.
        readonly property bool revealed: rowHover.hovered || row.activeFocus
            || actionsScope.activeFocus
        readonly property string glyph: T3Code.threadProviderIcon(thread.id)
        readonly property string statusWord: {
            if (entry.snoozed)
                return thread.snoozedUntil
                    ? "wakes in " + T3Code.snoozeWakeLabel(thread.snoozedUntil) : "snoozed";
            if (entry.settled)
                return T3Code.relTime(thread.settledAt || thread.updatedAt);
            if (thread.cls === "attention") {
                const kind = thread.pendingApprovals ? "approval"
                    : thread.pendingInput ? "input" : "waiting";
                const when = T3Code.relTime(thread.updatedAt);
                return when !== "" ? kind + " · " + when : kind;
            }
            if (thread.cls === "error") {
                const when = T3Code.relTime(thread.updatedAt);
                return when !== "" ? "error · " + when : "error";
            }
            if (thread.planReady)
                return "plan ready";
            if (thread.cls === "running") {
                const timer = T3Code.workingTimerLabel(thread.workingStartedAt);
                return timer !== "" ? "working " + timer : "working…";
            }
            if (thread.cls === "done") {
                const when = T3Code.relTime(thread.updatedAt);
                return when !== "" ? "done · " + when : "done";
            }
            return T3Code.relTime(thread.updatedAt);
        }
        readonly property color statusColor: thread.cls === "error" ? Theme.redText
            : thread.cls === "attention" ? Theme.amber
            : entry.quiet ? Theme.textDim
            : Theme.accent

        width: parent.width
        spacing: 3

        Rectangle {
            id: row
            width: parent.width
            height: 50
            radius: 9
            color: rowHover.hovered ? Theme.hoverFill : "transparent"
            border.width: activeFocus ? 1 : 0
            border.color: Theme.accent
            activeFocusOnTab: true

            // A passive handler keeps the row hovered while the pointer is
            // over one of its child actions. A MouseArea loses containsMouse
            // to those children, which made the actions and status alternate.
            HoverHandler {
                id: rowHover
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                        || event.key === Qt.Key_Space) {
                    root.threadRequested(entry.thread.id);
                    event.accepted = true;
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                onClicked: root.threadRequested(entry.thread.id)
            }

            Item {
                id: glyphSlot
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 15
                height: 15

                Image {
                    visible: entry.glyph !== ""
                    anchors.fill: parent
                    sourceSize: Qt.size(30, 30)
                    fillMode: Image.PreserveAspectFit
                    source: entry.glyph !== "" ? Quickshell.shellDir + "/assets/" + entry.glyph
                        + (entry.quiet ? "-dim" : "") + ".svg" : ""
                    opacity: entry.quiet ? 0.7 : 1
                }

                Rectangle {
                    visible: entry.glyph === ""
                    anchors.centerIn: parent
                    width: 7
                    height: 7
                    radius: 4
                    color: entry.quiet ? Theme.dotDim : entry.statusColor
                }
            }

            Column {
                anchors.left: glyphSlot.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Item {
                    width: parent.width
                    height: 17

                    Text {
                        anchors.left: parent.left
                        anchors.right: side.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.thread.title
                        elide: Text.ElideRight
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        font.weight: entry.quiet ? 500 : 600
                        color: entry.quiet ? Theme.textMid : Theme.textHi
                    }

                    Item {
                        id: side
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: entry.revealed ? actionsScope.implicitWidth
                            : statusText.implicitWidth
                        height: parent.height

                        Text {
                            id: statusText
                            visible: !entry.revealed
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: entry.statusWord
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            font.weight: 500
                            color: entry.statusColor
                        }

                        FocusScope {
                            id: actionsScope
                            visible: entry.revealed
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: actions.implicitWidth
                            implicitHeight: actions.implicitHeight

                            Row {
                                id: actions
                                spacing: 4

                                Action {
                                    visible: entry.active && T3Code.supportsSettlement
                                    revealed: entry.revealed
                                    label: T3Code.actionPending("settle", entry.thread.id, "")
                                        ? "…" : "Settle"
                                    enabled: T3Code.canDispatch && entry.thread.canLifecycle
                                        && !T3Code.actionPending("settle", entry.thread.id, "")
                                    tint: Theme.accent
                                    fill: Theme.accentBg
                                    onTriggered: T3Code.settle(entry.thread.id)
                                }

                                Action {
                                    visible: entry.settled && T3Code.supportsSettlement
                                    revealed: entry.revealed
                                    label: T3Code.actionPending("unsettle", entry.thread.id, "")
                                        ? "…" : "Unsettle"
                                    enabled: T3Code.canDispatch
                                        && !T3Code.actionPending("unsettle", entry.thread.id, "")
                                    tint: Theme.accent
                                    fill: Theme.accentBg
                                    onTriggered: T3Code.unsettle(entry.thread.id)
                                }

                                Action {
                                    visible: entry.snoozed && T3Code.supportsSnooze
                                    revealed: entry.revealed
                                    label: T3Code.actionPending("unsnooze", entry.thread.id, "")
                                        ? "…" : "Wake"
                                    enabled: T3Code.canDispatch
                                        && !T3Code.actionPending("unsnooze", entry.thread.id, "")
                                    tint: Theme.accent
                                    fill: Theme.accentBg
                                    onTriggered: T3Code.unsnooze(entry.thread.id)
                                }

                                Action {
                                    revealed: entry.revealed
                                    label: "↗"
                                    onTriggered: {
                                        Quickshell.execDetached(["xdg-open",
                                            T3Code.threadUrl(entry.thread.id)]);
                                        Popouts.close();
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: {
                        const parts = [];
                        if (entry.thread.project !== "")
                            parts.push(entry.thread.project);
                        if (entry.thread.cls === "error")
                            parts.push("session error");
                        else if (entry.settled)
                            parts.push(entry.thread.settledOverride === "settled"
                                ? "settled by you" : "settled by inactivity");
                        else if (entry.thread.cls === "attention"
                                && entry.thread.sessionStatus !== ""
                                && entry.thread.sessionStatus !== "running")
                            parts.push(entry.thread.sessionStatus);
                        return parts.join(" · ");
                    }
                    elide: Text.ElideRight
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    color: entry.thread.cls === "error" ? Theme.redText : Theme.textLow
                }
            }
        }

        Text {
            visible: text !== ""
            x: 33
            width: parent.width - 39
            text: {
                for (const kind of ["settle", "unsettle", "snooze", "unsnooze"]) {
                    const error = T3Code.actionError(kind, entry.thread.id, "");
                    if (error !== "")
                        return error;
                }
                return "";
            }
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: Theme.fontSans
            font.pixelSize: 10
            color: Theme.redText
        }
    }

    component DrawerHeader: Rectangle {
        id: drawer
        property string label: ""
        property int count: 0
        property bool expanded: false
        signal toggled()

        height: 30
        radius: 7
        color: drawerMouse.containsMouse ? Theme.hoverFill : Theme.cardFill
        activeFocusOnTab: true
        border.width: activeFocus ? 1 : 0
        border.color: Theme.accent

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                drawer.toggled();
                event.accepted = true;
            }
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: drawer.label
                font.family: Theme.fontSans
                font.pixelSize: 11
                font.weight: 600
                color: Theme.textLow
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: drawer.count
                font.family: Theme.fontMono
                font.pixelSize: 10
                font.weight: 500
                color: Theme.textDim
            }
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            text: drawer.expanded ? "▴" : "▾"
            font.family: Theme.fontMono
            font.pixelSize: 9
            color: Theme.textDim
        }

        MouseArea {
            id: drawerMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: drawer.toggled()
        }
    }

    Item {
        id: viewport
        width: parent.width
        height: Math.min(root.maxHeight, body.implicitHeight)

        Flickable {
            id: flick
            anchors.fill: parent
            contentWidth: width
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            activeFocusOnTab: interactive

            Column {
                id: body
                width: flick.width - (flick.contentHeight > flick.height ? 5 : 0)
                spacing: 4

                Text {
                    visible: T3Code.readOnly
                    width: parent.width
                    leftPadding: 7
                    rightPadding: 7
                    topPadding: 5
                    bottomPadding: 5
                    text: "Read-only pairing · actions are disabled"
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    color: Theme.amber
                }

                Text {
                    visible: T3Code.state !== "connected"
                    width: parent.width
                    topPadding: 12
                    bottomPadding: 12
                    text: T3Code.state === "unpaired" ? "Pair T3 Code to view threads"
                        : T3Code.state === "connecting" ? "Connecting…"
                        : "Server unreachable — drafts are safe"
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    color: Theme.textDim
                }

                Text {
                    visible: T3Code.state === "connected" && T3Code.shellReady
                        && T3Code.threads.length === 0 && T3Code.snoozedThreads.length === 0
                        && T3Code.settledThreads.length === 0
                    width: parent.width
                    topPadding: 12
                    bottomPadding: 12
                    text: "No sessions"
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    color: Theme.textDim
                }

                GroupHeader {
                    visible: root.needsYou.length > 0
                    label: "NEEDS YOU"
                    count: root.needsYou.length
                    tint: Theme.amber
                }
                Repeater {
                    model: root.needsYou
                    delegate: ThreadRow { required property var modelData; thread: modelData }
                }

                GroupHeader {
                    visible: root.readyPlans.length > 0
                    label: "READY TO REVIEW"
                    count: root.readyPlans.length
                    tint: Theme.accent
                }
                Repeater {
                    model: root.readyPlans
                    delegate: ThreadRow { required property var modelData; thread: modelData }
                }

                GroupHeader {
                    visible: root.runningThreads.length > 0
                    label: "WORKING"
                    count: root.runningThreads.length
                }
                Repeater {
                    model: root.runningThreads
                    delegate: ThreadRow { required property var modelData; thread: modelData }
                }

                Repeater {
                    model: root.quietThreads
                    delegate: ThreadRow { required property var modelData; thread: modelData }
                }

                Row {
                    id: drawerRow
                    visible: T3Code.snoozedThreads.length > 0 || T3Code.settledThreads.length > 0
                    width: parent.width
                    spacing: 6

                    readonly property bool both: T3Code.snoozedThreads.length > 0
                        && T3Code.settledThreads.length > 0

                    DrawerHeader {
                        visible: T3Code.snoozedThreads.length > 0
                        width: drawerRow.both ? (drawerRow.width - drawerRow.spacing) / 2
                            : drawerRow.width
                        label: "Snoozed"
                        count: T3Code.snoozedThreads.length
                        expanded: root.snoozedExpanded
                        onToggled: root.snoozedExpanded = !root.snoozedExpanded
                    }

                    DrawerHeader {
                        visible: T3Code.settledThreads.length > 0
                        width: drawerRow.both ? (drawerRow.width - drawerRow.spacing) / 2
                            : drawerRow.width
                        label: "Settled"
                        count: T3Code.settledThreads.length
                        expanded: root.settledExpanded
                        onToggled: root.settledExpanded = !root.settledExpanded
                    }
                }

                Repeater {
                    model: root.snoozedExpanded ? T3Code.snoozedThreads.slice(0, 5) : []
                    delegate: ThreadRow { required property var modelData; thread: modelData }
                }

                Text {
                    visible: root.snoozedExpanded && T3Code.snoozedThreads.length > 5
                    width: parent.width
                    leftPadding: 9
                    text: "+" + (T3Code.snoozedThreads.length - 5) + " more in T3 Code"
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    color: Theme.textDim
                }

                Repeater {
                    model: root.settledExpanded ? T3Code.settledThreads.slice(0, 5) : []
                    delegate: ThreadRow { required property var modelData; thread: modelData }
                }

                Text {
                    visible: root.settledExpanded && T3Code.settledThreads.length > 5
                    width: parent.width
                    leftPadding: 9
                    text: "+" + (T3Code.settledThreads.length - 5) + " more in T3 Code"
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    color: Theme.textDim
                }
            }
        }

        Rectangle {
            visible: flick.contentHeight > flick.height + 1
            anchors.right: parent.right
            width: 2
            height: Math.max(24, viewport.height * flick.visibleArea.heightRatio)
            y: flick.visibleArea.yPosition * viewport.height
            radius: 1
            color: Theme.textFaint
            opacity: flick.moving ? 0.8 : 0.4
        }
    }
}
