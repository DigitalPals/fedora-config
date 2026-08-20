pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../Common"

Column {
    id: root

    property int maxHeight: 560
    property bool snoozedExpanded: false
    property bool settledExpanded: false
    property string searchText: ""
    signal threadRequested(string threadId)

    readonly property int totalThreadCount: T3Code.threads.length
        + T3Code.pinnedThreads.length + T3Code.snoozedThreads.length
        + T3Code.settledThreads.length
    readonly property var pinnedThreads: filtered(T3Code.pinnedThreads)
    readonly property var snoozedThreads: filtered(T3Code.snoozedThreads)
    readonly property var settledThreads: filtered(T3Code.settledThreads)
    readonly property var needsYou: filtered(T3Code.threads).filter(thread =>
        thread.cls === "attention" || thread.cls === "error")
    readonly property var readyPlans: filtered(T3Code.threads).filter(thread =>
        thread.planReady && thread.cls !== "attention" && thread.cls !== "error")
    readonly property var runningThreads: filtered(T3Code.threads).filter(thread =>
        (thread.cls === "running" || thread.cls === "monitoring") && !thread.planReady)
    readonly property var quietThreads: filtered(T3Code.threads).filter(thread =>
        (thread.cls === "done" || thread.cls === "idle") && !thread.planReady)

    spacing: 5

    function filtered(threads) {
        const query = searchText.trim().toLowerCase();
        if (query === "")
            return Array.isArray(threads) ? threads : [];
        return (Array.isArray(threads) ? threads : []).filter(thread =>
            [thread.title, thread.project, thread.branch, thread.sessionStatus]
                .some(value => String(value ?? "").toLowerCase().includes(query)));
    }

    // The page's own T3 defaults over the shell's shared action primitive.
    component Action: ActionButton {
        fontFamily: T3Theme.fontSans
        focusColor: T3Theme.focus
        buttonRadius: T3Theme.controlRadius
        tint: T3Theme.textMuted
        fill: T3Theme.hover
    }

    component T3Status: StatusPlaceholder {
        fontFamily: T3Theme.fontSans
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
        height: 30

        Text {
            id: groupLabel
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: group.label
            font.family: T3Theme.fontSans
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.weightSemibold
            font.letterSpacing: 0.1
            color: group.tint
        }

        Text {
            id: groupCount
            anchors.left: groupLabel.right
            anchors.leftMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            text: group.count
            font.family: T3Theme.fontSans
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.weightMedium
            font.features: T3Theme.tabularNumberFeatures
            color: T3Theme.textFaint
        }

        Rectangle {
            anchors.left: groupCount.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: group.rule
        }
    }

    component ThreadRow: Column {
        id: entry
        required property var thread

        readonly property bool active: thread.lifecycle === "active"
        readonly property bool settled: thread.lifecycle === "settled"
        readonly property bool snoozed: thread.lifecycle === "snoozed"
        readonly property bool pinned: thread.pinned === true
        readonly property bool quiet: settled || snoozed
            || thread.cls === "done" || thread.cls === "idle"
        readonly property bool compact: quiet && !pinned
        readonly property bool flagged: thread.cls === "error" || thread.cls === "attention"
        readonly property bool revealed: rowHover.hovered || row.activeFocus
            || actionsScope.activeFocus
        readonly property string glyph: T3Code.threadProviderIcon(thread.id)
        readonly property string statusSymbol: thread.cls === "error" ? "error"
            : thread.cls === "attention" ? "help"
            : thread.planReady ? "description"
            : thread.cls === "running" ? "sync"
            : thread.cls === "monitoring" ? "visibility"
            : snoozed ? "snooze" : settled ? "archive" : "check_circle"
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
            if (thread.cls === "monitoring")
                return "monitoring";
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
        readonly property color statusColor: thread.cls === "error" ? T3Theme.red
            : thread.cls === "attention" ? T3Theme.amber
            : entry.quiet ? T3Theme.textFaint : T3Theme.accent

        width: parent.width
        spacing: 3

        Rectangle {
            id: row
            width: parent.width
            height: entry.compact ? T3Theme.quietRowHeight : T3Theme.activeRowHeight
            radius: T3Theme.rowRadius
            color: entry.flagged ? (entry.thread.cls === "error"
                    ? T3Theme.redSoft : T3Theme.amberSoft)
                : entry.compact ? "transparent" : T3Theme.surface
            border.width: activeFocus || entry.flagged || !entry.compact ? 1 : 0
            border.color: activeFocus ? T3Theme.focus
                : entry.thread.cls === "error" ? T3Theme.redBorder
                : entry.thread.cls === "attention" ? T3Theme.amberBorder : T3Theme.border
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: entry.thread.title + ", " + entry.statusWord
            Accessible.onPressAction: root.threadRequested(entry.thread.id)

            HoverHandler { id: rowHover }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                        || event.key === Qt.Key_Space) {
                    root.threadRequested(entry.thread.id);
                    event.accepted = true;
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.threadRequested(entry.thread.id)
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: rowHover.hovered ? T3Theme.hoverStrong : "transparent"

                Behavior on color {
                    ColorAnimation { duration: T3Theme.fastDuration }
                }
            }

            Item {
                id: glyphSlot
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: entry.compact ? 14 : 18
                height: width

                Image {
                    visible: entry.glyph !== ""
                    anchors.fill: parent
                    sourceSize: Qt.size(36, 36)
                    fillMode: Image.PreserveAspectFit
                    source: entry.glyph !== ""
                        ? Quickshell.shellDir + "/assets/" + entry.glyph + ".svg" : ""
                    opacity: entry.compact ? 0.58 : 0.92
                }

                Sym {
                    visible: entry.glyph === ""
                    anchors.centerIn: parent
                    name: "terminal"
                    size: entry.compact ? Theme.iconTiny : Theme.iconSmall
                    symWeight: 450
                    color: entry.compact ? T3Theme.textFaint : T3Theme.textMuted
                }

                Rectangle {
                    visible: entry.flagged || entry.thread.cls === "running"
                        || entry.thread.cls === "monitoring" || entry.thread.planReady
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: -2
                    width: 9
                    height: 9
                    radius: 5
                    color: entry.compact ? T3Theme.canvas : row.color

                    Rectangle {
                        anchors.centerIn: parent
                        width: 6
                        height: 6
                        radius: 3
                        color: entry.statusColor
                    }
                }
            }

            Column {
                anchors.left: glyphSlot.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Item {
                    width: parent.width
                    height: Math.max(threadTitle.implicitHeight, statusText.implicitHeight,
                        actionsScope.implicitHeight)

                    Text {
                        id: threadTitle
                        anchors.left: parent.left
                        anchors.right: side.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.thread.title
                        elide: Text.ElideRight
                        font.family: T3Theme.fontSans
                        font.pixelSize: Theme.fontBody
                        font.weight: entry.compact ? Theme.weightMedium : Theme.weightSemibold
                        color: entry.compact ? T3Theme.textSecondary : T3Theme.textPrimary
                    }

                    Item {
                        id: side
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: entry.revealed ? actionsScope.implicitWidth
                            : statusRow.implicitWidth
                        height: parent.height

                        Row {
                            id: statusRow
                            visible: !entry.revealed
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Sym {
                                anchors.verticalCenter: parent.verticalCenter
                                name: entry.statusSymbol
                                size: Theme.iconTiny
                                symWeight: 500
                                color: entry.statusColor
                            }

                            Text {
                                id: statusText
                                anchors.verticalCenter: parent.verticalCenter
                                text: entry.statusWord
                                font.family: T3Theme.fontSans
                                font.pixelSize: Theme.fontCaption
                                font.weight: Theme.weightMedium
                                font.features: T3Theme.tabularNumberFeatures
                                color: entry.statusColor
                            }
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
                                    visible: T3Code.supportsPinning
                                    revealed: entry.revealed
                                    hPadding: 12
                                    readonly property string kind: entry.thread.pinned
                                        ? "unpin" : "pin"
                                    label: T3Code.actionPending(kind, entry.thread.id, "")
                                        ? "…" : (entry.thread.pinned ? "Unpin" : "Pin")
                                    enabled: T3Code.canDispatch
                                        && !T3Code.actionPending(kind, entry.thread.id, "")
                                    onTriggered: entry.thread.pinned
                                        ? T3Code.unpin(entry.thread.id) : T3Code.pin(entry.thread.id)
                                }

                                Action {
                                    visible: entry.active && T3Code.supportsSettlement
                                    revealed: entry.revealed
                                    hPadding: 12
                                    label: T3Code.actionPending("settle", entry.thread.id, "")
                                        ? "…" : "Settle"
                                    enabled: T3Code.canDispatch && entry.thread.canLifecycle
                                        && !T3Code.actionPending("settle", entry.thread.id, "")
                                    tint: T3Theme.accent
                                    fill: T3Theme.accentSoft
                                    onTriggered: T3Code.settle(entry.thread.id)
                                }

                                Action {
                                    visible: entry.settled && T3Code.supportsSettlement
                                    revealed: entry.revealed
                                    hPadding: 12
                                    label: T3Code.actionPending("unsettle", entry.thread.id, "")
                                        ? "…" : "Unsettle"
                                    enabled: T3Code.canDispatch
                                        && !T3Code.actionPending("unsettle", entry.thread.id, "")
                                    tint: T3Theme.accent
                                    fill: T3Theme.accentSoft
                                    onTriggered: T3Code.unsettle(entry.thread.id)
                                }

                                Action {
                                    visible: entry.snoozed && T3Code.supportsSnooze
                                    revealed: entry.revealed
                                    hPadding: 12
                                    label: T3Code.actionPending("unsnooze", entry.thread.id, "")
                                        ? "…" : "Wake"
                                    enabled: T3Code.canDispatch
                                        && !T3Code.actionPending("unsnooze", entry.thread.id, "")
                                    tint: T3Theme.accent
                                    fill: T3Theme.accentSoft
                                    onTriggered: T3Code.unsnooze(entry.thread.id)
                                }

                                Action {
                                    revealed: entry.revealed
                                    hPadding: 12
                                    label: "Open"
                                    tint: T3Theme.accent
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
                    visible: !entry.compact
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
                    font.family: T3Theme.fontSans
                    font.pixelSize: Theme.fontSecondary
                    color: entry.thread.cls === "error" ? T3Theme.red : T3Theme.textFaint
                }
            }
        }

        Text {
            visible: text !== ""
            x: 38
            width: parent.width - 46
            text: {
                for (const kind of ["pin", "unpin", "settle", "unsettle", "snooze", "unsnooze"]) {
                    const error = T3Code.actionError(kind, entry.thread.id, "");
                    if (error !== "")
                        return error;
                }
                return "";
            }
            wrapMode: Text.WordWrap
            lineHeight: Theme.proseLineHeight
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: T3Theme.fontSans
            font.pixelSize: Theme.fontCaption
            color: T3Theme.red
        }
    }

    component DrawerHeader: Rectangle {
        id: drawer
        property string label: ""
        property int count: 0
        property bool expanded: false
        property bool subdued: false
        signal toggled()

        height: 36
        radius: T3Theme.controlRadius
        color: drawerMouse.containsMouse ? T3Theme.hoverStrong
            : drawer.subdued ? "transparent" : T3Theme.surface
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: drawer.label + ", " + drawer.count
        Accessible.onPressAction: drawer.toggled()
        border.width: activeFocus ? 1 : 0
        border.color: T3Theme.focus

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
                font.family: T3Theme.fontSans
                font.pixelSize: Theme.fontSecondary
                font.weight: drawer.subdued ? Theme.weightRegular : Theme.weightSemibold
                color: drawer.subdued ? T3Theme.textFaint : T3Theme.textMuted
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: drawer.count
                font.family: T3Theme.fontSans
                font.pixelSize: Theme.fontCaption
                font.weight: Theme.weightMedium
                font.features: T3Theme.tabularNumberFeatures
                color: T3Theme.textFaint
            }
        }

        Sym {
            anchors.right: parent.right
            anchors.rightMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            name: drawer.expanded ? "expand_less" : "expand_more"
            size: Theme.iconSmall
            symWeight: 450
            color: T3Theme.textFaint
        }

        MouseArea {
            id: drawerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
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

                Rectangle {
                    id: searchBox
                    visible: root.totalThreadCount > 6 || root.searchText !== ""
                    width: parent.width
                    height: 36
                    radius: T3Theme.controlRadius
                    color: T3Theme.surface
                    border.width: searchInput.activeFocus ? 1 : 0
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
                        id: searchInput
                        anchors.left: parent.left
                        anchors.leftMargin: 32
                        anchors.right: clearSearch.visible ? clearSearch.left : parent.right
                        anchors.rightMargin: clearSearch.visible ? 4 : 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.searchText
                        onTextEdited: root.searchText = text
                        clip: true
                        selectByMouse: true
                        font.family: T3Theme.fontSans
                        font.pixelSize: Theme.fontSecondary
                        color: T3Theme.textPrimary

                        Text {
                            visible: searchInput.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search threads"
                            font.family: T3Theme.fontSans
                            font.pixelSize: Theme.fontSecondary
                            color: T3Theme.textFaint
                        }
                    }

                    IconButton {
                        id: clearSearch
                        visible: searchInput.text !== ""
                        anchors.right: parent.right
                        anchors.rightMargin: 5
                        anchors.verticalCenter: parent.verticalCenter
                        controlSize: 26
                        symbol: "close"
                        accessibleName: "Clear thread search"
                        tint: T3Theme.textFaint
                        onTriggered: {
                            root.searchText = "";
                            searchInput.text = "";
                            searchInput.forceActiveFocus();
                        }
                    }
                }

                Text {
                    visible: T3Code.readOnly
                    width: parent.width
                    leftPadding: 7
                    rightPadding: 7
                    topPadding: 5
                    bottomPadding: 5
                    text: "Read-only access · actions are disabled"
                    font.family: T3Theme.fontSans
                    font.pixelSize: Theme.fontSecondary
                    color: T3Theme.amber
                }

                T3Status {
                    shown: T3Code.state !== "connected"
                    width: parent.width
                    kind: T3Code.cloudLoginRunning || T3Code.state === "connecting" ? "loading"
                        : T3Code.state === "signed-out" || T3Code.state === "cloud-empty"
                            ? "empty" : "error"
                    glyph: {
                        if (T3Code.state === "signed-out")
                            return "cloud";
                        if (T3Code.state === "cloud-empty")
                            return "cloud_off";
                        if (kind === "error")
                            return "cloud_off";
                        return "progress_activity";
                    }
                    title: T3Code.cloudLoginRunning ? "Finish in your browser"
                        : T3Code.state === "signed-out"
                            ? "T3 Connect"
                        : T3Code.state === "cloud-empty" ? "No linked T3 environments"
                        : T3Code.state === "connecting" ? "Connecting through T3 Connect…"
                        : "Server unreachable — drafts are safe"
                    detail: T3Code.cloudLoginRunning
                        ? "Choose Google or GitHub in the browser to continue."
                        : T3Code.state === "signed-out"
                            ? "Sign in with Google or GitHub to access your linked environments."
                        : T3Code.state === "cloud-empty"
                            ? "You're signed in, but this account has no linked environments."
                        : ""
                }

                Action {
                    visible: T3Code.state === "signed-out" || T3Code.state === "cloud-empty"
                        || T3Code.cloudLoginRunning
                    anchors.horizontalCenter: parent.horizontalCenter
                    label: T3Code.cloudLoginRunning ? "Waiting for browser…"
                        : T3Code.state === "cloud-empty" ? "Refresh"
                        : "Sign in"
                    hPadding: 22
                    enabled: !T3Code.cloudLoginRunning
                    tint: T3Theme.accent
                    fill: T3Theme.accentSubtle
                    onTriggered: T3Code.loginCloud()
                }

                Text {
                    visible: T3Code.cloudLoginRunning
                    width: Math.min(parent.width - 24, 390)
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: T3Code.cloudLoginRunning
                        ? "This panel will reconnect automatically."
                        : ""
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeight: Theme.proseLineHeight
                    font.family: T3Theme.fontSans
                    font.pixelSize: Theme.fontCaption
                    color: T3Theme.textFaint
                }

                Text {
                    visible: T3Code.state === "cloud-empty"
                    width: Math.min(parent.width - 24, 390)
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Link an environment in T3 Code Nightly, then refresh."
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeight: Theme.proseLineHeight
                    font.family: T3Theme.fontSans
                    font.pixelSize: Theme.fontCaption
                    color: T3Theme.textFaint
                }

                Text {
                    visible: T3Code.cloudLoginError !== ""
                    width: Math.min(parent.width - 24, 390)
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: T3Code.cloudLoginError
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.family: T3Theme.fontSans
                    font.pixelSize: Theme.fontCaption
                    color: T3Theme.red
                }

                T3Status {
                    shown: T3Code.state === "connected" && T3Code.shellReady
                        && T3Code.threads.length === 0 && T3Code.pinnedThreads.length === 0
                        && T3Code.snoozedThreads.length === 0
                        && T3Code.settledThreads.length === 0
                    width: parent.width
                    glyph: "forum"
                    title: "No sessions"
                }

                Text {
                    visible: root.searchText !== "" && root.pinnedThreads.length === 0
                        && root.needsYou.length === 0 && root.readyPlans.length === 0
                        && root.runningThreads.length === 0 && root.quietThreads.length === 0
                        && root.snoozedThreads.length === 0 && root.settledThreads.length === 0
                    width: parent.width
                    topPadding: 24
                    bottomPadding: 24
                    text: "No threads match “" + root.searchText + "”"
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    font.family: T3Theme.fontSans
                    font.pixelSize: Theme.fontSecondary
                    color: T3Theme.textFaint
                }

                // Pinned first, like the reference sidebar. Rows keep their
                // live status word, so a pinned thread that needs you still
                // reads amber — it is just anchored here instead of sorted.
                GroupHeader {
                    visible: root.pinnedThreads.length > 0
                    label: "Pinned"
                    count: root.pinnedThreads.length
                }
                Repeater {
                    model: root.pinnedThreads
                    delegate: ThreadRow { required property var modelData; thread: modelData }
                }

                GroupHeader {
                    visible: root.needsYou.length > 0
                    label: "Needs you"
                    count: root.needsYou.length
                    tint: T3Theme.amber
                    rule: T3Theme.amberBorder
                }
                Repeater {
                    model: root.needsYou
                    delegate: ThreadRow { required property var modelData; thread: modelData }
                }

                GroupHeader {
                    visible: root.readyPlans.length > 0
                    label: "Ready to review"
                    count: root.readyPlans.length
                    tint: T3Theme.accent
                    rule: T3Theme.accentSoft
                }
                Repeater {
                    model: root.readyPlans
                    delegate: ThreadRow { required property var modelData; thread: modelData }
                }

                GroupHeader {
                    visible: root.runningThreads.length > 0
                    label: "Working"
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
                    visible: root.snoozedThreads.length > 0 || root.settledThreads.length > 0
                    width: parent.width
                    spacing: 6

                    readonly property bool both: root.snoozedThreads.length > 0
                        && root.settledThreads.length > 0

                    DrawerHeader {
                        visible: root.snoozedThreads.length > 0
                        width: drawerRow.both ? (drawerRow.width - drawerRow.spacing) / 2
                            : drawerRow.width
                        label: "Snoozed"
                        count: root.snoozedThreads.length
                        expanded: root.snoozedExpanded
                        onToggled: root.snoozedExpanded = !root.snoozedExpanded
                    }

                    DrawerHeader {
                        visible: root.settledThreads.length > 0
                        width: drawerRow.both ? (drawerRow.width - drawerRow.spacing) / 2
                            : drawerRow.width
                        label: "Settled"
                        count: root.settledThreads.length
                        expanded: root.settledExpanded
                        subdued: true
                        onToggled: root.settledExpanded = !root.settledExpanded
                    }
                }

                Repeater {
                    model: root.snoozedExpanded ? root.snoozedThreads.slice(0, 5) : []
                    delegate: ThreadRow { required property var modelData; thread: modelData }
                }

                Text {
                    visible: root.snoozedExpanded && root.snoozedThreads.length > 5
                    width: parent.width
                    leftPadding: 9
                    text: "+" + (root.snoozedThreads.length - 5) + " more in T3 Code"
                    font.family: T3Theme.fontSans
                    font.pixelSize: Theme.fontCaption
                    color: T3Theme.textFaint
                }

                Repeater {
                    model: root.settledExpanded ? root.settledThreads.slice(0, 5) : []
                    delegate: ThreadRow { required property var modelData; thread: modelData }
                }

                Text {
                    visible: root.settledExpanded && root.settledThreads.length > 5
                    width: parent.width
                    leftPadding: 9
                    text: "+" + (root.settledThreads.length - 5) + " more in T3 Code"
                    font.family: T3Theme.fontSans
                    font.pixelSize: Theme.fontCaption
                    color: T3Theme.textFaint
                }
            }
        }

        ScrollChrome {
            anchors.fill: parent
            target: flick
            edgeColor: T3Theme.canvas
            thumbColor: T3Theme.accent
        }
    }
}
