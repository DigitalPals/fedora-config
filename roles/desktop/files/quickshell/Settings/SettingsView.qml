pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import "../Common"
import "../Popovers"

// Connected center-island settings surface (design 1c, grouped rail):
// search on top of the rail, nav grouped under SHELL / SYSTEM, and the
// save state in the rail footer. The host supplies the usable output
// envelope before measuring implicit size.
PopoutPanel {
    id: root

    // Defaults for an unhosted instance; the host assigns both.
    availableWidth: 760
    availableHeight: 560
    readonly property bool compactNav: availableWidth < 680
    readonly property int headerHeight: 44
    readonly property int gutter: 12
    readonly property int navWidth: compactNav ? 52 : 168
    readonly property int preferredWidth: 760
    readonly property int preferredHeight: 660
    readonly property int pageIndex: Math.max(0,
        navItems.findIndex(item => item.id === Settings.page))
    readonly property bool dragActive: pageLoader.item
        ? (pageLoader.item.dragActive ?? false) : false

    implicitWidth: Math.max(320, Math.min(preferredWidth, availableWidth))
    implicitHeight: Math.max(280, Math.min(preferredHeight, availableHeight))
    focus: true

    readonly property var navItems: [
        { id: "appearance", group: "SHELL", label: "Appearance", glyph: "",
            title: "Appearance", description: "Shape, typography, and shell accent",
            keywords: "bar height corner radius menu font accent color hue wallpaper theme" },
        { id: "wallpaper", group: "SHELL", label: "Wallpaper", glyph: "",
            title: "Wallpaper", description: "Desktop image and automatic rotation",
            keywords: "desktop image background picture folder shuffle rotation" },
        { id: "bar", group: "SHELL", label: "Bar layout", glyph: "",
            title: "Bar layout", description: "Position, spacing, and monitor behavior",
            keywords: "position top bottom floating gap auto hide exclusive monitor" },
        { id: "modules", group: "SHELL", label: "Modules", glyph: "",
            title: "Modules", description: "Choose and arrange the bar’s contents",
            keywords: "clock weather media workspaces volume wifi battery bluetooth arrange order" },
        { id: "notifications", group: "SYSTEM", label: "Notifications", glyph: "",
            title: "Notifications", description: "Toasts, quiet hours, and the notification center",
            keywords: "toast do not disturb dnd quiet hours duration position density icons timeout progress body preview test" },
        { id: "system", group: "SYSTEM", label: "System", glyph: "",
            title: "System", description: "Formats, night light, OSD, and storage",
            keywords: "clock format temperature unit scroll speed night light warmth osd poll usage config reset" }
    ]

    // ---- rail search -----------------------------------------------------
    property string navQuery: ""

    function matchesQuery(item) {
        const query = navQuery.trim().toLowerCase();
        if (query === "")
            return true;
        return (item.label + " " + item.keywords).toLowerCase().indexOf(query) !== -1;
    }

    readonly property var visibleNav: navItems.filter(item => matchesQuery(item))

    function navDelegate(id) {
        for (const repeater of [shellRepeater, systemRepeater]) {
            for (let i = 0; i < repeater.count; i++) {
                const item = repeater.itemAt(i);
                if (item && item.modelData.id === id)
                    return item;
            }
        }
        return null;
    }

    function selectVisible(position) {
        if (visibleNav.length === 0)
            return;
        const clamped = Math.max(0, Math.min(visibleNav.length - 1, position));
        Settings.page = visibleNav[clamped].id;
        const item = navDelegate(visibleNav[clamped].id);
        if (item)
            item.forceActiveFocus();
    }

    function selectOffset(delta) {
        const current = visibleNav.findIndex(item => item.id === Settings.page);
        selectVisible(current === -1 ? 0 : current + delta);
    }

    function clearSearch() {
        searchInput.text = "";
        navQuery = "";
    }

    function cancelDrag() {
        if (pageLoader.item && pageLoader.item.cancelDrag)
            pageLoader.item.cancelDrag();
    }

    // Called by IslandPopout. A module drag consumes the first Escape, an
    // open module sub-page the next, an active rail search the one after.
    function handleEscape(): bool {
        if (dragActive) {
            cancelDrag();
            return true;
        }
        if (pageLoader.item && (pageLoader.item.subPageActive ?? false)) {
            pageLoader.item.closeSubPage();
            return true;
        }
        if (navQuery !== "") {
            clearSearch();
            return true;
        }
        return false;
    }

    component NavItem: Rectangle {
        id: navItem
        required property var modelData
        required property int index
        readonly property bool current: Settings.page === modelData.id

        width: navColumn.width
        height: visible ? 34 : 0
        visible: root.matchesQuery(modelData)
        radius: Theme.rowRadius
        color: current ? Theme.accentBg
            : navMouse.pressed ? Theme.hoverFillStrong
            : navMouse.containsMouse || activeFocus ? Theme.hoverFill : "transparent"
        border.width: activeFocus ? 1 : 0
        border.color: Theme.accent
        activeFocusOnTab: navItem.current
        Accessible.role: Accessible.PageTab
        Accessible.name: navItem.modelData.label
        Accessible.selected: navItem.current
        Accessible.onPressAction: Settings.page = navItem.modelData.id
        Controls.ToolTip.visible: root.compactNav && navMouse.containsMouse
        Controls.ToolTip.text: navItem.modelData.label

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
                root.selectOffset(-1); event.accepted = true;
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
                root.selectOffset(1); event.accepted = true;
            } else if (event.key === Qt.Key_Home) {
                root.selectVisible(0); event.accepted = true;
            } else if (event.key === Qt.Key_End) {
                root.selectVisible(root.visibleNav.length - 1); event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                Settings.page = modelData.id; event.accepted = true;
            }
        }

        Text {
            id: navIcon
            anchors.left: parent.left
            anchors.leftMargin: root.compactNav ? 0 : 11
            anchors.verticalCenter: parent.verticalCenter
            width: root.compactNav ? parent.width : 20
            horizontalAlignment: Text.AlignHCenter
            text: navItem.modelData.glyph
            font.family: Theme.fontIcon
            font.pixelSize: Theme.iconMedium
            color: navItem.current ? Theme.accent : Theme.icon
        }

        Text {
            visible: !root.compactNav
            anchors.left: navIcon.right
            anchors.leftMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            text: navItem.modelData.label
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontSecondary
            font.weight: navItem.current ? Theme.weightSemibold : Theme.weightMedium
            color: navItem.current ? Theme.textHi : Theme.textLow
        }

        MouseArea {
            id: navMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Settings.page = navItem.modelData.id;
                navItem.forceActiveFocus();
            }
        }
    }

    component GroupLabel: Item {
        property alias text: labelText.text
        property int topPad: 6
        width: navColumn.width
        height: visible ? 18 + topPad : 0

        Text {
            id: labelText
            anchors.left: parent.left
            anchors.leftMargin: 11
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.weightSemibold
            font.letterSpacing: 0.8
            color: Theme.textFaint
        }
    }

    Item {
        id: header
        width: parent.width
        height: root.headerHeight

        Column {
            anchors.left: parent.left
            anchors.leftMargin: root.gutter
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                text: root.navItems[root.pageIndex].title
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontHeading
                font.weight: Theme.weightSemibold
                color: Theme.textHi
            }

            Text {
                visible: root.width >= 520
                text: root.navItems[root.pageIndex].description
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: Theme.textDim
            }
        }

        SettingsAction {
            anchors.right: closeAction.left
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            visible: Settings.sectionDirty(Settings.page)
            text: "Reset page"
            glyph: "↺"
            onTriggered: Settings.resetSection(Settings.page)
        }

        SettingsAction {
            id: closeAction
            anchors.right: parent.right
            anchors.rightMargin: root.gutter
            anchors.verticalCenter: parent.verticalCenter
            compact: true
            text: "Close"
            glyph: "×"
            onTriggered: Settings.closePanel()
        }
    }

    Rectangle {
        y: root.headerHeight
        width: parent.width
        height: 1
        color: Theme.hairlineSoft
    }

    Item {
        id: body
        y: root.headerHeight + 1
        width: parent.width
        height: parent.height - root.headerHeight - 1

        Column {
            id: navColumn
            x: root.gutter / 2
            y: root.gutter
            width: root.navWidth - root.gutter
            spacing: 3

            Rectangle {
                id: searchBox
                visible: !root.compactNav
                width: parent.width
                height: 28
                radius: 7
                color: searchInput.activeFocus ? Theme.hoverFillStrong : Theme.cardFill
                border.width: searchInput.activeFocus ? 1 : 0
                border.color: Theme.accent

                Text {
                    id: searchGlyph
                    anchors.left: parent.left
                    anchors.leftMargin: 9
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    font.family: Theme.fontIcon
                    font.pixelSize: Theme.iconSmall
                    color: Theme.textFaint
                }

                TextInput {
                    id: searchInput
                    anchors.left: searchGlyph.right
                    anchors.leftMargin: 6
                    anchors.right: searchClear.visible ? searchClear.left : parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textHi
                    selectionColor: Theme.accentBg
                    selectedTextColor: Theme.textHi
                    clip: true
                    activeFocusOnTab: true
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Search settings"
                    onTextChanged: root.navQuery = text

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape && text !== "") {
                            root.clearSearch(); event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                || event.key === Qt.Key_Down) {
                            root.selectVisible(0); event.accepted = true;
                        }
                    }

                    Text {
                        visible: searchInput.text === ""
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Search settings"
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontCaption
                        color: Theme.textFaint
                        elide: Text.ElideRight
                    }
                }

                Text {
                    id: searchClear
                    visible: searchInput.text !== ""
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "×"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontSecondary
                    color: clearMouse.containsMouse ? Theme.textHi : Theme.textDim

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.clearSearch()
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    visible: !searchInput.activeFocus
                    cursorShape: Qt.IBeamCursor
                    onClicked: searchInput.forceActiveFocus()
                }
            }

            GroupLabel {
                text: "SHELL"
                topPad: 3
                visible: !root.compactNav
                    && root.visibleNav.some(item => item.group === "SHELL")
            }

            Repeater {
                id: shellRepeater
                model: root.navItems.filter(item => item.group === "SHELL")
                delegate: NavItem {}
            }

            GroupLabel {
                text: "SYSTEM"
                visible: !root.compactNav
                    && root.visibleNav.some(item => item.group === "SYSTEM")
            }

            Repeater {
                id: systemRepeater
                model: root.navItems.filter(item => item.group === "SYSTEM")
                delegate: NavItem {}
            }

            Text {
                visible: !root.compactNav && root.visibleNav.length === 0
                width: parent.width
                leftPadding: 11
                topPadding: 6
                text: "No matches"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: Theme.textFaint
            }
        }

        // Save state lives in the rail footer (design 1c).
        Column {
            id: railFooter
            anchors.left: parent.left
            anchors.leftMargin: root.gutter / 2
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.gutter - 2
            width: root.navWidth - root.gutter
            spacing: 5

            SettingsAction {
                visible: Settings.undoAvailable
                height: 26
                text: "Undo"
                glyph: "↺"
                Accessible.name: "Undo " + Settings.resetLabel + " reset"
                onTriggered: Settings.undoReset()
            }

            SettingsAction {
                visible: Settings.saveError && !Settings.undoAvailable
                height: 26
                text: "Retry"
                glyph: "↻"
                onTriggered: Settings.retrySave()
            }

            Row {
                spacing: 7
                leftPadding: root.compactNav ? 0 : 11
                width: parent.width

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6; height: 6; radius: 3
                    color: Settings.undoAvailable ? Theme.accent
                        : Settings.saveError ? Theme.red
                        : Settings.savePending ? Theme.amber : Theme.connected
                }

                Text {
                    visible: !root.compactNav
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 6 - 7 - parent.leftPadding
                    text: Settings.undoAvailable ? Settings.resetLabel + " reset"
                        : Settings.saveError ? "Could not save"
                        : Settings.savePending ? "Saving changes…"
                        : Settings.font === "mono" ? "Saved · live" : "Saved · applies live"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    color: Settings.saveError ? Theme.redText : Theme.textFaint
                    elide: Text.ElideRight
                    Accessible.role: Settings.saveError
                        ? Accessible.AlertMessage : Accessible.StaticText
                    Accessible.name: text
                }
            }
        }

        Rectangle {
            x: root.navWidth
            width: 1
            height: parent.height
            color: Theme.hairlineSoft
        }

        Loader {
            id: pageLoader
            // Incubated off the frame that opens the panel: the pages are the
            // bulk of this view and building one inline stalls the popout's
            // open animation. The loader is explicitly sized, so a page that
            // is one frame late changes nothing but its own content area, and
            // every reader below already tolerates a null item.
            asynchronous: true
            x: root.navWidth + root.gutter
            y: root.gutter
            width: parent.width - root.navWidth - root.gutter * 2
            height: parent.height - root.gutter * 2
            focus: true
            sourceComponent: {
                switch (Settings.page) {
                case "wallpaper": return wallpaperPage;
                case "bar": return barPage;
                case "modules": return modulesPage;
                case "notifications": return notificationsPage;
                case "system": return systemPage;
                default: return appearancePage;
                }
            }
        }

        Component { id: appearancePage; AppearancePage {} }
        Component { id: wallpaperPage; WallpaperPage {} }
        Component { id: barPage; BarLayoutPage {} }
        Component { id: modulesPage; ModulesPage {} }
        Component { id: notificationsPage; NotificationsPage {} }
        Component { id: systemPage; SystemPage {} }
    }

    Item {
        width: 1
        height: 1
        opacity: 0
        Accessible.role: Accessible.AlertMessage
        Accessible.name: Settings.announcement
    }
}
