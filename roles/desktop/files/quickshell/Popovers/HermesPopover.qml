pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

// Full Hermes menubar mini-client: connection health, native WebUI conversation
// history, streaming chat, tool/request activity and durable context.
Surface {
    id: root

    spacing: 6
    padding: HermesTheme.pagePadding
    surfaceColor: HermesTheme.canvas
    surfaceBorderColor: HermesTheme.borderStrong

    availableWidth: 680 - Theme.barSideMargin * 2
    availableHeight: 900 - Theme.barTopMargin - Theme.barHeight - 16
    implicitWidth: Math.max(Theme.t3MinWidth,
        Math.min(640, root.availableWidth))

    readonly property int maxBodyHeight: Math.max(420, root.availableHeight
        - root.padding * 2 - HermesTheme.headerHeight - footer.height
        - root.spacing * 2)

    property bool setupOpen: false
    readonly property bool showingSetup: setupOpen
        || Hermes.bridgeReady && Hermes.setupRequired

    function handleEscape(): bool {
        if (showingSetup && setupOpen && Hermes.agentReady) {
            setupOpen = false;
            authPanel.clearSecret();
            return true;
        }
        return !showingSetup && inbox.handleEscape();
    }

    Claim {
        active: root.visible
        onClaimed: {
            Hermes.setPopoverVisible(true);
            if (Hermes.bridgeReady) {
                Hermes.refreshRemoteStatus();
                Hermes.refreshProviderStatus();
            }
            if (!Hermes.conversationsReady || Hermes.conversations.length === 0)
                Hermes.refresh();
        }
        onReleased: {
            Hermes.setPopoverVisible(false);
            authPanel.clearSecret();
        }
    }

    Item {
        id: header
        width: parent.width
        height: HermesTheme.headerHeight

        Rectangle {
            x: -root.padding
            y: parent.height - 1
            width: root.width
            height: 1
            color: HermesTheme.border
        }

        Text {
            id: hermesMark
            anchors.left: parent.left
            anchors.leftMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            text: "⚕"
            font.family: HermesTheme.fontUi
            font.pixelSize: Theme.iconLarge
            font.weight: Theme.weightSemibold
            color: Hermes.agentReady ? HermesTheme.accent
                : Hermes.bridgeReady ? HermesTheme.amber : HermesTheme.textFaint
            Accessible.ignored: true
        }

        Column {
            anchors.left: hermesMark.right
            anchors.leftMargin: 8
            anchors.right: headerActions.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: "Hermes Agent"
                elide: Text.ElideRight
                font.family: HermesTheme.fontUi
                font.pixelSize: Theme.fontBody
                font.weight: Theme.weightSemibold
                color: HermesTheme.textPrimary
            }

            Row {
                spacing: 6

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 5
                    height: 5
                    radius: 3
                    color: !Hermes.connected ? HermesTheme.red
                        : !Hermes.bridgeReady || Hermes.remoteLoading
                            ? HermesTheme.amber : Hermes.remoteSessionExpired
                                ? HermesTheme.amber : !Hermes.remoteConfigured
                                && (Hermes.backendStatus === "reconnecting"
                                || Hermes.backendStatus === "error"
                                || Hermes.backendStatus === "offline"
                                || Hermes.backendStatus === "unavailable")
                                    ? HermesTheme.red : Hermes.setupRequired
                                        ? HermesTheme.amber : HermesTheme.success
                }

                Text {
                    width: Math.max(0, header.width - headerActions.width - 78)
                    text: {
                        if (!Hermes.connected)
                            return Hermes.connectionError || "Bridge offline";
                        if (!Hermes.bridgeReady)
                            return Hermes.bridgeError || "Starting…";
                        if (Hermes.remoteLoading)
                            return "Checking remote Hermes session…";
                        if (Hermes.remoteSessionExpired)
                            return "Session sign-in required · remote WebUI session expired";
                        if (Hermes.remoteConnected)
                            return "Remote · " + Hermes.remoteOrigin;
                        if (Hermes.remoteConfigured && Hermes.remoteError !== "")
                            return Hermes.remoteError;
                        if (Hermes.remoteConfigured)
                            return "Remote sign-in required · " + Hermes.remoteOrigin;
                        if (Hermes.backendError !== "" && !Hermes.localProviderReady)
                            return Hermes.backendError;
                        if (!Hermes.remoteConfigured && Hermes.localProviderReady)
                            return "Local · " + Hermes.providerName + " · "
                                + Hermes.providerModel;
                        return Hermes.localBackendAvailable
                            ? "Connect a Hermes WebUI · local provider setup is advanced"
                            : "Connect a remote Hermes WebUI";
                    }
                    elide: Text.ElideRight
                    font.family: HermesTheme.fontUi
                    font.pixelSize: Theme.fontCaption
                    color: HermesTheme.textFaint
                }
            }
        }

        Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            IconButton {
                symbol: "refresh"
                accessibleName: "Refresh Hermes status"
                tint: HermesTheme.textMuted
                onTriggered: Hermes.refresh()
            }

            IconButton {
                symbol: "key"
                accessibleName: root.showingSetup
                    ? "Return to Hermes conversations" : "Hermes connection setup"
                tint: root.showingSetup ? HermesTheme.accent : HermesTheme.textMuted
                enabled: Hermes.bridgeReady
                onTriggered: {
                    if (Hermes.agentReady)
                        root.setupOpen = !root.setupOpen;
                    else
                        root.setupOpen = true;
                }
            }

            IconButton {
                symbol: "add_comment"
                accessibleName: "New Hermes chat"
                tint: Hermes.isNewChat ? HermesTheme.accent : HermesTheme.textMuted
                enabled: Hermes.canOperate
                onTriggered: Hermes.startNewChat()
            }
        }
    }

    HermesInboxPage {
        id: inbox
        visible: !root.showingSetup
        width: parent.width
        height: visible ? root.maxBodyHeight : 0
        maxHeight: root.maxBodyHeight
    }

    HermesAuthPanel {
        id: authPanel
        visible: root.showingSetup
        width: parent.width
        height: visible ? authPanel.implicitHeight : 0
        maxHeight: root.maxBodyHeight
        onConfigured: root.setupOpen = false
        onCloseRequested: {
            root.setupOpen = false;
            clearSecret();
        }
    }

    Item {
        id: footer
        width: parent.width
        height: HermesTheme.footerHeight

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: HermesTheme.border
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.68
            text: Hermes.remoteConnected ? Hermes.remoteOrigin
                : Hermes.remoteConfigured ? Hermes.remoteOrigin + " · sign-in required"
                : Hermes.localProviderReady ? Hermes.providerName + " · " + Hermes.providerModel
                : Hermes.connected ? "local transport · "
                    + Hermes.endpoint.replace(/^wss?:\/\//, "")
                    : "Hermes reconnects automatically"
            elide: Text.ElideMiddle
            font.family: HermesTheme.fontMono
            font.pixelSize: Theme.fontMicro
            color: HermesTheme.textFaint
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Hermes.remoteSessionExpired ? "session expired"
                : !Hermes.agentReady ? "sign-in required"
                : Hermes.workingCount > 0 ? Hermes.workingCount + " working"
                : Hermes.attentionCount > 0 ? Hermes.attentionCount + " waiting"
                    : Hermes.conversations.length + " conversations"
            font.family: HermesTheme.fontUi
            font.pixelSize: Theme.fontMicro
            font.features: HermesTheme.tabularNumberFeatures
            color: Hermes.attentionCount > 0 ? HermesTheme.amber
                : HermesTheme.textFaint
        }
    }
}
