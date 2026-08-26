import QtQuick
import "../Common"

Item {
    id: root

    property string contextThreadId: ""
    property int maxHeight: 640
    signal backRequested()

    readonly property var draft: T3Code.newThreadDraft
    readonly property var projects: T3Code.sortedProjects().map(project => ({
        id: project.id, label: project.title
    }))
    readonly property real projectPopupBottom: projectShoulder.y + projectPicker.y
        + projectPicker.popupItem.y + projectPicker.popupHeight
    readonly property real baseFormBottom: {
        if (pendingText.visible)
            return pendingText.y + pendingText.height;
        if (actionErrorText.visible)
            return actionErrorText.y + actionErrorText.height;
        return composer.y + composer.height;
    }
    readonly property real projectPickerNeededHeight: projectPicker.expanded
        ? Math.max(0, projectPopupBottom - baseFormBottom) : 0
    // A visible Column child also contributes the gap before it. Include that
    // gap in the declared growth so the card/background split stays exact.
    readonly property real projectPickerLayoutHeight: projectPickerNeededHeight > 0
        ? Math.max(form.spacing, projectPickerNeededHeight) : 0
    readonly property real activePickerLayoutHeight: projectPicker.expanded
        ? projectPickerLayoutHeight : composer.barPickerLayoutHeight
    readonly property Item activePopupItem: projectPicker.expanded
        ? projectPicker.popupItem : composer.activeBarPopupItem
    // Only the part by which the viewport actually grew is outside the normal
    // card. On a height-capped output the remainder stays inside the scrolling
    // page, so it must not be subtracted from the card background.
    readonly property real detachedOverflowHeight: {
        const overflow = root.activePickerLayoutHeight;
        if (overflow <= 0)
            return 0;
        const limit = root.maxHeight - header.height - 6;
        const baseFormHeight = Math.max(0, form.implicitHeight - overflow);
        const baseViewportHeight = Math.max(150, Math.min(limit, baseFormHeight));
        return Math.max(0, viewport.height - baseViewportHeight);
    }
    readonly property Item detachedOverflowItem: detachedOverflowHeight > 0
        ? root.activePopupItem : null

    implicitHeight: header.height + 6 + viewport.height

    // Contextual page header replaces the inbox brand header while composing.
    Item {
        id: header
        width: parent.width
        height: Theme.controlHeight

        IconButton {
            id: backButton
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            symbol: "arrow_back"
            accessibleName: "Back to inbox"
            onTriggered: root.backRequested()
        }

        Text {
            anchors.left: backButton.right
            anchors.leftMargin: 9
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "New thread"
            elide: Text.ElideRight
            font.family: T3Theme.fontUi
            font.pixelSize: Theme.fontBody
            font.weight: Theme.weightSemibold
            color: T3Theme.textPrimary
        }
    }

    Item {
        id: viewport
        anchors.top: header.bottom
        anchors.topMargin: 6
        width: parent.width
        height: Math.max(150, Math.min(root.maxHeight - header.height - 6, form.implicitHeight))

        Flickable {
            id: flick
            anchors.fill: parent
            contentWidth: width
            contentHeight: form.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            activeFocusOnTab: interactive

            Column {
                id: form
                width: flick.width - (flick.contentHeight > flick.height ? 5 : 0)
                spacing: 4

                Rectangle {
                    visible: !T3Code.hasReadyProvider
                    width: parent.width
                    height: configText.implicitHeight + 14
                    radius: T3Theme.panelRadius
                    color: T3Theme.amberSoft
                    border.width: 1
                    border.color: T3Theme.amberBorder

                    Text {
                        id: configText
                        x: 7
                        y: 7
                        width: parent.width - 14
                        text: T3Code.configLoading ? "Loading provider configuration…"
                            : T3Code.configError !== "" ? T3Code.configError
                            : T3Code.configReady
                                ? "No enabled provider with an advertised model is ready."
                                : "A ready provider configuration is required."
                        wrapMode: Text.WordWrap
                        lineHeight: Theme.proseLineHeight
                        font.family: T3Theme.fontUi
                        font.pixelSize: Theme.fontCaption
                        color: T3Theme.amber
                    }
                }

                Rectangle {
                    id: projectShoulder
                    width: parent.width
                    height: 44
                    z: projectPicker.expanded ? 200 : 0
                    radius: T3Theme.panelRadius
                    color: T3Theme.surfaceRaised
                    border.width: 1
                    border.color: T3Theme.border

                    T3Picker {
                        id: projectPicker
                        anchors.fill: parent
                        anchors.margins: 5
                        label: "Project"
                        value: root.draft.projectId ?? ""
                        options: root.projects
                        openUpward: false
                        enabled: T3Code.hasReadyProvider && root.draft.projectFixed !== true
                            && !T3Code.actionPending("new", "", "")
                        onSelected: value => T3Code.setNewProject(value)
                        onExpandedChanged: Qt.callLater(() => {
                            if (expanded)
                                flick.contentY = Math.max(0,
                                    root.projectPopupBottom - flick.height);
                            else
                                flick.returnToBounds();
                        })
                    }
                }

                Text {
                    visible: root.draft.projectFixed === true
                    width: parent.width
                    text: "This plan stays in the source project and Default mode. Provider, model, traits, and access remain adjustable."
                    wrapMode: Text.WordWrap
                    lineHeight: Theme.proseLineHeight
                    font.family: T3Theme.fontUi
                    font.pixelSize: Theme.fontCaption
                    color: T3Theme.textFaint
                }

                T3Composer {
                    id: composer
                    width: parent.width
                    newThread: true
                    editable: T3Code.state === "connected" && T3Code.hasReadyProvider
                        && T3Code.canDispatch && !T3Code.actionPending("new", "", "")
                    sendEnabled: editable && root.draft.projectId !== ""
                    sendLabel: "Start"
                    onSendRequested: T3Code.submitNewThread()
                    onBarPickerReserveChanged: Qt.callLater(() => {
                        if (barPickerReserve > 0)
                            flick.contentY = Math.max(0, flick.contentHeight - flick.height);
                        else
                            flick.returnToBounds();
                    })
                }

                Text {
                    id: actionErrorText
                    visible: T3Code.actionError("new", "", "") !== ""
                    width: parent.width
                    text: T3Code.actionError("new", "", "")
                    wrapMode: Text.WordWrap
                    lineHeight: Theme.proseLineHeight
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    font.family: T3Theme.fontUi
                    font.pixelSize: Theme.fontCaption
                    color: T3Theme.red
                }

                Text {
                    id: pendingText
                    visible: T3Code.actionPending("new", "", "")
                    width: parent.width
                    text: T3Code.pendingNewThreadId !== ""
                        ? "Creating thread and waiting for shell confirmation…" : "Creating thread…"
                    font.family: T3Theme.fontUi
                    font.pixelSize: Theme.fontCaption
                    color: T3Theme.textFaint
                }

                // Like the composer's bar-menu spacer, this is geometry only:
                // the host leaves the added tail transparent while the Project
                // menu paints over it and remains part of the input mask.
                Item {
                    id: projectPickerSpace
                    visible: root.projectPickerLayoutHeight > 0
                    width: parent.width
                    height: Math.max(0,
                        root.projectPickerLayoutHeight - form.spacing)
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

    Component.onCompleted: {
        T3Code.ensureNewThreadDraft(contextThreadId);
        composer.syncPrompt();
        composer.focusPrompt();
    }
}
