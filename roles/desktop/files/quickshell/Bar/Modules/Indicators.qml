pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../../Common"

// Clock-side quick actions. Inactive and active actions live in distinct
// blocks: disclosure grows outward, while active actions stay pinned against
// the clock and newly activated ones enter at that block's outer edge.
BarModule {
    id: root

    moduleId: "indicators"
    readonly property string panelName: "reminders"
    spacing: 2
    property bool disclosureLatched: false
    property bool orderReady: false
    property var activeOrder: []
    property var actionButtons: []

    readonly property var actions: [
        { id: "dictation", glyph: "mic" },
        { id: "recording", glyph: "radio_button_checked" },
        { id: "reminder", glyph: "notifications_active" },
        { id: "night-light", glyph: "nightlight" },
        { id: "dnd", glyph: "do_not_disturb_on" },
        { id: "stay-awake", glyph: "coffee" }
    ]
    readonly property string actionStateKey: [
        Dictation.state, Recorder.active, Reminders.count,
        SysInfo.nightLight, Notifs.dnd, SysInfo.idleInhibited
    ].join(":")
    readonly property bool reminderOpen: host !== null
        && host.popoutOpen("reminders")
    readonly property bool revealInactive: Settings.modOpts.indicators.mode === "always"
        || disclosureLatched || reminderOpen
    readonly property bool disclosureAnimating: inactiveRevealer.widthAnimating
    readonly property var inactiveActions: {
        void actionStateKey;
        return actions.filter(action => !isActive(action.id));
    }
    readonly property var activeActions: {
        void actionStateKey;
        return activeOrder.map(id => actionFor(id)).filter(action => action !== null);
    }

    function actionFor(id) {
        return actions.find(action => action.id === id) ?? null;
    }

    function isActive(id) {
        switch (id) {
        case "dictation": return Dictation.busy;
        case "recording": return Recorder.active;
        case "reminder": return Reminders.count > 0;
        case "night-light": return SysInfo.nightLight;
        case "dnd": return Notifs.dnd;
        case "stay-awake": return SysInfo.idleInhibited;
        default: return false;
        }
    }

    function syncActiveOrder() {
        const current = actions.filter(action => isActive(action.id)).map(action => action.id);
        if (!orderReady) {
            activeOrder = current;
            orderReady = true;
            return;
        }
        let next = activeOrder.filter(id => current.indexOf(id) !== -1);
        // Unshift puts a new state on the outer (left) edge. Existing actions
        // therefore keep their screen position against the pinned clock.
        for (const id of current) {
            if (next.indexOf(id) === -1)
                next.unshift(id);
        }
        activeOrder = next;
    }

    function registerAction(button) {
        if (actionButtons.indexOf(button) === -1)
            actionButtons = actionButtons.concat([button]);
        if (host !== null && button.actionId === "reminder")
            host.registerPanel("reminders", button);
    }

    function unregisterAction(button) {
        actionButtons = actionButtons.filter(candidate => candidate !== button);
        if (host !== null && button.actionId === "reminder")
            host.unregisterPanel("reminders", button);
    }

    function actionAtScenePoint(position: point): bool {
        for (const button of actionButtons) {
            if (!button || !button.visible || button.width <= 0)
                continue;
            const local = button.mapFromItem(null, position.x, position.y);
            if (local.x >= 0 && local.x <= button.width
                    && local.y >= 0 && local.y <= button.height)
                return true;
        }
        return false;
    }

    function tooltipFor(id) {
        switch (id) {
        case "dictation":
            return Dictation.recording ? "Stop dictation"
                : Dictation.transcribing ? "Cancel transcription"
                : "Dictate · English click · Dutch middle click";
        case "recording":
            return Recorder.active ? "Stop recording" + (Recorder.outputFile !== ""
                ? " · " + Recorder.outputFile.split("/").pop() : "")
                : "Record a selected region";
        case "reminder": return Reminders.tooltip;
        case "night-light": return SysInfo.nightLight ? "Turn off night light" : "Turn on night light";
        case "dnd": return Notifs.dnd ? "Turn off Do Not Disturb" : "Turn on Do Not Disturb";
        case "stay-awake": return SysInfo.idleInhibited ? "Allow idle and sleep" : "Stay awake";
        default: return "";
        }
    }

    function trigger(id, button, mouseButton) {
        switch (id) {
        case "dictation":
            Dictation.toggle(mouseButton === Qt.MiddleButton ? "nl" : "en");
            break;
        case "recording": Recorder.toggle(); break;
        case "reminder": host.togglePopout("reminders", isle, button); break;
        case "night-light": SysInfo.toggleNightLight(); break;
        case "dnd": Notifs.setDnd(!Notifs.dnd); break;
        case "stay-awake": SysInfo.toggleIdleInhibited(); break;
        }
    }

    onGroupHoveredChanged: {
        if (groupHovered) {
            collapseDelay.stop();
            disclosureLatched = true;
        }
    }

    onHostChanged: {
        if (host === null)
            return;
        host.indicatorDisclosureAnimating = disclosureAnimating;
        for (const button of actionButtons) {
            if (button.actionId === "reminder")
                host.registerPanel("reminders", button);
        }
    }

    onDisclosureAnimatingChanged: {
        if (host !== null)
            host.indicatorDisclosureAnimating = disclosureAnimating;
    }

    Connections {
        target: root.host
        enabled: root.host !== null

        function onTooltipPointerInsideChanged() {
            if (root.host.tooltipPointerInside) {
                collapseDelay.stop();
            } else if (!root.reminderOpen
                    && Settings.modOpts.indicators.mode !== "always") {
                collapseDelay.restart();
            }
        }
    }

    Connections {
        target: Dictation
        function onStateChanged() { root.syncActiveOrder(); }
    }
    Connections {
        target: Recorder
        function onActiveChanged() { root.syncActiveOrder(); }
    }
    Connections {
        target: Reminders
        function onCountChanged() { root.syncActiveOrder(); }
    }
    Connections {
        target: SysInfo
        function onNightLightChanged() { root.syncActiveOrder(); }
        function onIdleInhibitedChanged() { root.syncActiveOrder(); }
    }
    Connections {
        target: Notifs
        function onDndChanged() { root.syncActiveOrder(); }
    }
    Connections {
        target: Popouts
        function onChanged() {
            if (root.reminderOpen) {
                collapseDelay.stop();
                root.disclosureLatched = true;
            } else if (root.host !== null && !root.host.tooltipPointerInside
                    && Settings.modOpts.indicators.mode !== "always") {
                collapseDelay.restart();
            }
        }
    }

    Timer {
        id: collapseDelay
        interval: 180
        onTriggered: {
            if (root.host !== null && !root.host.tooltipPointerInside
                    && !root.reminderOpen
                    && Settings.modOpts.indicators.mode !== "always")
                root.disclosureLatched = false;
        }
    }

    component IndicatorAction: Rectangle {
        id: button
        required property var modelData
        readonly property string actionId: modelData.id
        readonly property bool activeState: root.isActive(actionId)
        readonly property bool recording: actionId === "recording" && Recorder.active
        readonly property bool transcribing: actionId === "dictation" && Dictation.transcribing
        readonly property string actionLabel: recording ? Recorder.elapsedLabel : ""
        readonly property color ink: recording ? Theme.barRedFg
            : activeState ? Theme.barAccent
            : hovered ? Theme.barTextHi : Theme.barTextDim
        readonly property bool hovered: pointer.over

        height: Theme.chipInnerHeight
        width: contents.implicitWidth + (actionLabel === "" ? 12 : 16)
        radius: Theme.chipRadius
        color: recording ? Theme.barRed
            : hovered ? Theme.barChipHover : "transparent"
        scale: actionMouse.pressed ? 0.92 : 1
        Accessible.role: Accessible.Button
        Accessible.name: root.tooltipFor(actionId)
        Accessible.onPressAction: root.trigger(actionId, button, Qt.LeftButton)

        Behavior on width {
            NumberAnimation {
                duration: Theme.expandDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.springCurve
            }
        }
        Behavior on color { ColorAnimation { duration: Theme.chipFadeDuration } }
        Behavior on scale {
            NumberAnimation {
                duration: Theme.pressDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.springCurve
            }
        }

        PointerCheck {
            id: pointer
            host: root.host
            target: button
            hovered: actionMouse.containsMouse
        }

        Row {
            id: contents
            anchors.centerIn: parent
            spacing: button.actionLabel === "" ? 0 : 5

            Sym {
                id: actionGlyph
                anchors.verticalCenter: parent.verticalCenter
                name: button.transcribing ? "progress_activity" : button.modelData.glyph
                size: Theme.iconSmall + 2
                fill: button.activeState && !button.transcribing ? 1 : 0
                symWeight: 550
                color: button.ink

                RotationAnimation on rotation {
                    running: button.transcribing
                    from: 0
                    to: 360
                    duration: 850
                    loops: Animation.Infinite
                }

                SequentialAnimation on opacity {
                    running: button.recording
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 650; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
                }
            }

            Text {
                visible: button.actionLabel !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: button.actionLabel
                font.family: Theme.fontMenu
                font.pixelSize: Theme.barLabelSize
                font.weight: Theme.weightSemibold
                font.features: Theme.tabularNumberFeatures
                color: button.ink
            }
        }

        MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onEntered: {
                if (button.actionId === "reminder")
                    root.host.hoverPopout("reminders", root.isle, button);
            }
            onPositionChanged: {
                if (button.actionId === "reminder")
                    root.host.hoverPopout("reminders", root.isle, button);
            }
            onClicked: mouse => root.trigger(button.actionId, button, mouse.button)
        }

        BarTooltip {
            check: pointer
            text: root.tooltipFor(button.actionId)
            align: -1
            y: button.height + 8
            x: 0
        }

        Component.onCompleted: root.registerAction(button)
        Component.onDestruction: root.unregisterAction(button)
    }

    Revealer {
        id: inactiveRevealer
        orientation: Qt.Horizontal
        reveal: root.revealInactive
        opacity: reveal ? 0.58 : 0

        Row {
            spacing: 2
            Repeater {
                model: root.inactiveActions
                delegate: IndicatorAction {}
            }
        }
    }

    Row {
        spacing: 2
        Repeater {
            model: root.activeActions
            delegate: IndicatorAction {}
        }
    }

    Component.onCompleted: syncActiveOrder()
    Component.onDestruction: {
        if (host !== null)
            host.indicatorDisclosureAnimating = false;
    }
}
