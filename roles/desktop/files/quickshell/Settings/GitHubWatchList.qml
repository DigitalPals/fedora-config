pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/GitHubHelpers.js" as GitHubHelpers

// The two parts of the GitHub module's settings that are not value rows: who
// the shell is reading GitHub as, and which repositories outside that account
// join the feed.
//
// A watch entry is canonicalised here, at the point of entry, so a pasted
// browser URL or an SSH remote becomes "owner/repo" before it is stored —
// which is why SettingsHelpers.repoListIn only has to recognise the canonical
// form.
Column {
    id: root

    readonly property var watch: Settings.modOpts.gh.watch
    readonly property bool watchDirty: watch.length > 0

    property string addError: ""

    spacing: 8

    function addWatch(text) {
        const slug = GitHubHelpers.repoSlug(text);
        if (slug === "") {
            addError = "Not a repository — use owner/repo, or paste its GitHub URL";
            return false;
        }
        if (root.watch.some(entry => entry.toLowerCase() === slug.toLowerCase())) {
            addError = slug + " is already watched";
            return false;
        }
        if (root.watch.length >= GitHubHelpers.MAX_WATCH) {
            addError = "At most " + GitHubHelpers.MAX_WATCH + " watched repositories";
            return false;
        }
        addError = "";
        Settings.setModuleOption("gh", "watch", root.watch.concat([slug]));
        return true;
    }

    function removeWatch(slug) {
        addError = "";
        Settings.setModuleOption("gh", "watch",
            root.watch.filter(entry => entry !== slug));
    }

    // A 22px square beside a 28px row, the shape the Modules list already
    // uses for its per-row cog.
    component RowButton: Rectangle {
        id: button

        property string glyph: ""
        property string action: ""
        signal triggered()

        width: 22
        height: 22
        radius: 5
        color: buttonMouse.containsMouse || activeFocus ? Theme.hoverFill : "transparent"
        border.width: activeFocus ? 1 : 0
        border.color: Theme.accent
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: button.action
        Accessible.onPressAction: button.triggered()

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                button.triggered();
                event.accepted = true;
            }
        }

        Text {
            anchors.centerIn: parent
            text: button.glyph
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontSecondary
            color: buttonMouse.containsMouse ? Theme.textMid : Theme.textDim
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                button.forceActiveFocus();
                button.triggered();
            }
        }
    }

    // ---- account ----------------------------------------------------------
    SectionHeader {
        label: "ACCOUNT"
    }

    Rectangle {
        width: parent.width
        height: 52
        radius: Theme.rowRadius
        color: Theme.cardFill

        Text {
            id: markGlyph
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "\uf09b" // nf-fa-github
            font.family: Theme.fontIcon
            font.pixelSize: Theme.iconMedium
            color: Theme.icon
        }

        Row {
            id: connectionState
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            readonly property bool failed: GitHub.error !== ""
            // This page is reachable from the module row's cog whether or not
            // the module is on, and with it off nothing polls — so the card
            // says that rather than spinning on a check that will never run.
            readonly property bool off: !GitHub.pollEnabled

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 6
                height: 6
                radius: 3
                color: connectionState.off ? Theme.dotDim
                    : connectionState.failed ? Theme.red
                    : GitHub.ready ? Theme.connected : Theme.amber
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: connectionState.off ? "Module off"
                    : connectionState.failed ? "Unavailable"
                    : GitHub.ready ? "Connected" : "Checking…"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: Theme.textDim
            }
        }

        Column {
            anchors.left: markGlyph.right
            anchors.leftMargin: 10
            anchors.right: connectionState.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: GitHub.login !== "" ? "@" + GitHub.login
                    : GitHub.pollEnabled ? "Not signed in" : "gh CLI"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontSecondary
                font.weight: Theme.weightMedium
                color: Theme.textHi
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: {
                    if (!GitHub.pollEnabled)
                        return "Switch the module on to read your repositories";
                    if (GitHub.error !== "")
                        return GitHub.error;
                    if (!GitHub.ready)
                        return "Reading the gh CLI's login…";
                    const orgs = GitHub.orgCount;
                    return "Authenticated via gh CLI · " + GitHub.repos.length + " repos"
                        + (orgs > 0 ? " across " + orgs + (orgs === 1 ? " org" : " orgs") : "");
                }
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: GitHub.error !== "" ? Theme.redText : Theme.textLow
                elide: Text.ElideRight
            }
        }
    }

    // ---- watched repositories ---------------------------------------------
    SectionHeader {
        label: "WATCHED REPOS"
        dirty: root.watchDirty
        onResetRequested: {
            root.addError = "";
            Settings.setModuleOption("gh", "watch", []);
        }
    }

    Item {
        width: parent.width
        height: Theme.settingsControlHeight

        SettingsAction {
            id: addAction
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Add"
            glyph: "+"
            onTriggered: {
                if (root.addWatch(addInput.text))
                    addInput.text = "";
                addInput.forceActiveFocus();
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: addAction.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            height: Theme.settingsControlHeight
            radius: 7
            color: addInput.activeFocus ? Theme.hoverFillStrong : Theme.cardFill
            border.width: addInput.activeFocus ? 1 : 0
            border.color: root.addError !== "" ? Theme.red : Theme.accent

            TextInput {
                id: addInput
                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.right: parent.right
                anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: Theme.textHi
                selectionColor: Theme.accentBg
                selectedTextColor: Theme.textHi
                clip: true
                activeFocusOnTab: true
                Accessible.role: Accessible.EditableText
                Accessible.name: "Repository to watch"
                onTextChanged: root.addError = ""
                onAccepted: {
                    if (root.addWatch(text))
                        text = "";
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        text = "";
                        focus = false;
                        event.accepted = true;
                    }
                }

                Text {
                    visible: addInput.text === ""
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: "owner/repo"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textFaint
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                anchors.fill: parent
                visible: !addInput.activeFocus
                cursorShape: Qt.IBeamCursor
                onClicked: addInput.forceActiveFocus()
            }
        }
    }

    Text {
        visible: root.addError !== ""
        width: parent.width
        text: root.addError
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        color: Theme.redText
        wrapMode: Text.Wrap
    }

    Column {
        width: parent.width
        spacing: 3

        Repeater {
            model: root.watch

            delegate: Rectangle {
                id: watchRow

                required property string modelData

                width: parent.width
                height: Theme.settingsControlHeight
                radius: 7
                color: Theme.cardFill

                RowButton {
                    id: removeButton
                    anchors.right: parent.right
                    anchors.rightMargin: 3
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "×"
                    action: "Stop watching " + watchRow.modelData
                    onTriggered: root.removeWatch(watchRow.modelData)
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.right: removeButton.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    // The owner is dim and the name is not, the same split the
                    // popover's repository rows draw.
                    text: "<font color=\"" + Theme.textDim + "\">"
                        + watchRow.modelData.split("/")[0] + "/</font>"
                        + watchRow.modelData.split("/")[1]
                    textFormat: Text.StyledText
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textMid
                    elide: Text.ElideRight
                }
            }
        }
    }

    Text {
        width: parent.width
        text: "Your account's and org repos always show in the list. Watched repos add "
            + "outside sources to the feed, the badge and toasts."
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        color: Theme.textFaint
        wrapMode: Text.Wrap
    }
}
