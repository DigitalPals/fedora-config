pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "Common"
import "Popovers"

// Eight-result tabbed command palette. LauncherProviders owns routing,
// asynchronous work and activation; this permanently warm view renders
// normalized rows.
//
// Visual shape from the "QuickShell Menubar" design: a recessed search tile,
// 48px result rows with a 32px icon, the selected row lifted on the accent,
// and a hairline footer carrying the count and the key hints.
Surface {
    id: root

    implicitWidth: 560

    readonly property int maxResults: LauncherProviders.maxResults
    readonly property int rowHeight: 48
    property int selected: 0
    readonly property string query: search.text
    readonly property bool inputActiveFocus: search.activeFocus
    readonly property var provider: LauncherProviders.activeProvider
    readonly property string mode: LauncherProviders.mode
    readonly property string term: LauncherProviders.term
    readonly property var rows: LauncherProviders.rows
    readonly property var tabs: LauncherProviders.tabProviders
    readonly property string searchPlaceholder: ({
        apps: "Search applications",
        emoji: "Search emoji by name",
        clipboard: "Search clipboard history",
        actions: "Search actions"
    })[provider.id] || "Search apps, commands and more"

    // The view is permanently warm. Reset synchronously on open and ask for
    // focus both now and on the next event-loop turn: the second request
    // covers the layer-surface mapping without clearing any text typed in the
    // meantime.
    function focusInput(): void {
        search.forceActiveFocus();
    }

    function prepareOpen(): void {
        LauncherProviders.selectedProviderId = "apps";
        search.text = "";
        selected = 0;
        focusInput();
        Qt.callLater(() => {
            if (Launcher.open)
                root.focusInput();
        });
    }

    Component.onCompleted: {
        if (Launcher.open)
            prepareOpen();
    }

    Connections {
        target: Launcher

        function onOpenChanged() {
            if (Launcher.open)
                root.prepareOpen();
        }
    }

    onRowsChanged: selected = Math.min(selected, Math.max(0, rows.length - 1))
    onQueryChanged: {
        selected = 0;
        LauncherProviders.query = query;
    }

    function activate(row): void {
        LauncherProviders.activate(row);
    }

    function selectTab(providerId): void {
        LauncherProviders.selectedProviderId = providerId;
        search.text = "";
        selected = 0;
        focusInput();
    }

    function cycleTab(offset): void {
        let current = 0;
        const selectedId = root.tabs.some(tab => tab.id === root.provider.id)
            ? root.provider.id : LauncherProviders.selectedProviderId;
        for (let i = 0; i < root.tabs.length; ++i) {
            if (root.tabs[i].id === selectedId) {
                current = i;
                break;
            }
        }
        const next = (current + offset + root.tabs.length) % root.tabs.length;
        root.selectTab(root.tabs[next].id);
    }

    // Shared by the TextInput and by LauncherWindow's one-frame focus-race
    // fallback. Enter is intentionally handled regardless of modifiers, so
    // it can launch the selected first row even if Super has not yet lifted.
    function handleCommandKey(event): bool {
        if (event.key === Qt.Key_Escape) {
            Launcher.close();
        } else if (event.modifiers & Qt.ControlModifier
                && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
            cycleTab((event.key === Qt.Key_Backtab
                || event.modifiers & Qt.ShiftModifier) ? -1 : 1);
        } else if (event.key === Qt.Key_Left) {
            cycleTab(-1);
        } else if (event.key === Qt.Key_Right) {
            cycleTab(1);
        } else if (event.modifiers & Qt.AltModifier && event.key >= Qt.Key_1 && event.key <= Qt.Key_8) {
            activate(rows[event.key - Qt.Key_1]);
        } else if (event.modifiers & Qt.ShiftModifier
                && event.key === Qt.Key_Delete
                && LauncherProviders.canRemove(rows[selected])) {
            LauncherProviders.remove(rows[selected]);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            activate(rows[selected]);
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
            selected = Math.min(Math.max(0, rows.length - 1), selected + 1);
        } else if (event.key === Qt.Key_Up) {
            selected = Math.max(0, selected - 1);
        } else if (event.key === Qt.Key_Home) {
            selected = 0;
        } else if (event.key === Qt.Key_End) {
            selected = Math.max(0, rows.length - 1);
        } else {
            return false;
        }
        return true;
    }

    function handleEarlyKey(event): bool {
        if (handleCommandKey(event))
            return true;
        const commandModifiers = Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier;
        if (event.text === "" || event.modifiers & commandModifiers)
            return false;
        focusInput();
        search.insert(search.cursorPosition, event.text);
        return true;
    }

    function esc(value) {
        return (value || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function highlight(value, muted) {
        if (term === "" || muted)
            return esc(value);
        const index = (value || "").toLowerCase().indexOf(term.toLowerCase());
        if (index < 0)
            return esc(value);
        return esc(value.slice(0, index))
            + `<font color="${Theme.accent}">` + esc(value.slice(index, index + term.length)) + "</font>"
            + esc(value.slice(index + term.length));
    }

    // `muted` suppresses the accent match highlight — on the selected row the
    // accent is the background.
    function titleFor(row, muted) {
        if (!row)
            return "";
        return row.highlight === false ? esc(row.title)
            : highlight(row.title, muted);
    }

    // ---- Provider tabs ---------------------------------------------------
    Rectangle {
        width: parent.width
        height: 38
        radius: 15
        color: Theme.tile

        Row {
            id: tabRow
            x: 4
            y: 4
            width: parent.width - 8
            height: parent.height - 8
            spacing: 4

            Repeater {
                model: root.tabs

                delegate: Rectangle {
                    id: providerTab

                    required property var modelData
                    required property int index
                    readonly property bool active:
                        root.provider.id === modelData.id
                    readonly property string label: ({
                        apps: "Apps",
                        emoji: "Emoji",
                        clipboard: "History",
                        actions: "Actions"
                    })[modelData.id] || modelData.label

                    width: (tabRow.width - tabRow.spacing
                        * (root.tabs.length - 1)) / root.tabs.length
                    height: tabRow.height
                    radius: 11
                    color: active ? Theme.accentBg
                        : providerTabMouse.containsMouse
                            ? Theme.hoverFillStrong : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: Theme.chipFadeDuration }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 7

                        Sym {
                            anchors.verticalCenter: parent.verticalCenter
                            name: providerTab.modelData.glyph
                            size: Theme.fontSecondary
                            color: providerTab.active
                                ? Theme.accent : Theme.textDim
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: providerTab.label
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontTiny
                            font.weight: Theme.weightBold
                            color: providerTab.active
                                ? Theme.textHi : Theme.textDim
                        }
                    }

                    Accessible.role: Accessible.PageTab
                    Accessible.name: label
                    Accessible.selected: active
                    Accessible.onPressAction:
                        root.selectTab(providerTab.modelData.id)

                    MouseArea {
                        id: providerTabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectTab(providerTab.modelData.id)
                    }
                }
            }
        }
    }

    // ---- Search tile -----------------------------------------------------
    Rectangle {
        width: parent.width
        height: 48
        radius: 22
        color: Theme.tile

        Behavior on color {
            ColorAnimation { duration: Theme.surfaceDuration }
        }

        Sym {
            id: searchGlyph
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            name: root.provider.glyph
            size: 18
            color: Theme.textDim
        }

        TextInput {
            id: search
            anchors.verticalCenter: parent.verticalCenter
            x: 44
            width: parent.width - x - (modeChip.visible ? modeChip.width + 24 : 16)
            font.family: Theme.fontSans
            font.pixelSize: Theme.fontBody
            font.weight: Theme.weightSemibold
            color: Theme.textHi
            clip: true
            focus: Launcher.open

            Text {
                visible: search.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: root.searchPlaceholder
                font: search.font
                color: Theme.textDim
            }

            Keys.onPressed: event => event.accepted = root.handleCommandKey(event)
        }

        // A typed utility prefix temporarily overrides the selected tab.
        // Clicking its chip removes the prefix and returns to that tab.
        Rectangle {
            id: modeChip
            visible: root.mode !== ""
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: modeLabel.implicitWidth + 20
            height: 22
            radius: Theme.pillRadius
            color: modeMouse.containsMouse ? Theme.hoverFillStrong : Theme.chipHover

            Text {
                id: modeLabel
                anchors.centerIn: parent
                text: root.mode !== "" ? root.provider.label : ""
                font.family: Theme.fontSans
                font.pixelSize: Theme.fontMicro
                font.weight: Theme.weightHeavy
                font.letterSpacing: 0.5
                color: Theme.textHi
            }

            MouseArea {
                id: modeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: search.text = root.term
            }
        }
    }

    // ---- Results ---------------------------------------------------------
    ListView {
        id: resultList
        width: parent.width
        height: Math.min(root.maxResults, root.rows.length) * root.rowHeight
        interactive: false
        model: root.rows

        delegate: Rectangle {
            id: resultRow

            required property var modelData
            required property int index
            readonly property bool isSelected: index === root.selected
            readonly property string subtitle: modelData.subtitle || ""
            width: resultList.width
            height: root.rowHeight
            radius: Theme.rowRadius
            color: isSelected ? Theme.accent : "transparent"

            Behavior on color {
                ColorAnimation { duration: Theme.chipFadeDuration }
            }

            Item {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32

                Image {
                    anchors.fill: parent
                    visible: source !== ""
                    source: resultRow.modelData.icon
                        ? Quickshell.iconPath(resultRow.modelData.icon, true) : ""
                    sourceSize: Qt.size(64, 64)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                Rectangle {
                    visible: !resultRow.modelData.icon
                    anchors.fill: parent
                    radius: 10
                    color: Theme.chip

                    Sym {
                        anchors.centerIn: parent
                        visible: !resultRow.modelData.iconText
                        name: resultRow.modelData.glyph || root.provider.glyph
                        size: Theme.iconMedium
                        color: resultRow.isSelected ? Theme.textOnAccent : Theme.textMid
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !!resultRow.modelData.iconText
                        text: resultRow.modelData.iconText || ""
                        font.family: Theme.fontSans
                        font.pixelSize: 20
                    }
                }
            }

            Column {
                x: 54
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - 46
                spacing: 1

                Text {
                    width: parent.width
                    textFormat: Text.StyledText
                    text: root.titleFor(resultRow.modelData, resultRow.isSelected)
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontSecondary
                    font.weight: Theme.weightBold
                    color: resultRow.isSelected ? Theme.textOnAccent : Theme.textHi
                    elide: Text.ElideRight
                }

                Text {
                    visible: resultRow.subtitle !== ""
                    width: parent.width
                    text: resultRow.subtitle
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontMicro
                    font.weight: Theme.weightSemibold
                    color: resultRow.isSelected ? Qt.rgba(1, 1, 1, 0.78) : Theme.textDim
                    elide: Text.ElideMiddle
                }
            }

            Rectangle {
                visible: resultRow.isSelected
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: enterGlyph.implicitWidth + 12
                height: 18
                radius: 6
                color: Qt.rgba(1, 1, 1, 0.22)

                Text {
                    id: enterGlyph
                    anchors.centerIn: parent
                    text: "↵"
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontMicro
                    font.weight: Theme.weightHeavy
                    color: Theme.textOnAccent
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selected = resultRow.index
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton
                            && LauncherProviders.canRemove(resultRow.modelData))
                        LauncherProviders.remove(resultRow.modelData);
                    else
                        root.activate(resultRow.modelData);
                }
            }
        }
    }

    // ---- Empty state -----------------------------------------------------
    Column {
        visible: root.rows.length === 0
        width: parent.width
        topPadding: 18
        bottomPadding: 12
        spacing: 6

        Sym {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "search_off"
            size: Theme.iconLarge + 2
            color: Theme.textDim
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 40
            horizontalAlignment: Text.AlignHCenter
            text: LauncherProviders.emptyText
            font.family: Theme.fontSans
            font.pixelSize: Theme.fontTiny
            font.weight: Theme.weightBold
            color: LauncherProviders.error !== "" ? Theme.redText : Theme.textDim
            elide: Text.ElideRight
        }
    }

    HDivider {}

    // ---- Footer ----------------------------------------------------------
    Item {
        width: parent.width
        height: 20

        Text {
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - hints.width - 32
            text: LauncherProviders.footerLeft
            font.family: Theme.fontSans
            font.pixelSize: Theme.fontMicro
            font.weight: Theme.weightBold
            color: Theme.textDim
            elide: Text.ElideRight
        }

        Row {
            id: hints
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Repeater {
                model: [
                    "←→ tab",
                    "↑↓ select",
                    "↵ " + root.provider.enter
                ].concat(root.provider.id === "clipboard" ? [
                    "⇧⌫ remove"
                ] : []).concat([
                    "esc close"
                ])

                delegate: Text {
                    required property string modelData
                    text: modelData
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontMicro
                    font.weight: Theme.weightBold
                    color: Theme.textDim
                }
            }
        }
    }
}
