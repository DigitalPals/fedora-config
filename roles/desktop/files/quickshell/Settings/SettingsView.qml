pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import "../Common"
import "../Popovers"

// Connected center-island settings workspace with a labeled sidebar that
// collapses to an icon rail when the output cannot fit the preferred card.
PopoutPanel {
    id: root

    // Defaults for an unhosted instance; the host assigns both.
    availableWidth: 900
    availableHeight: 680
    readonly property bool compactNav: availableWidth < 860
    readonly property int headerHeight: 58
    readonly property int gutter: 14
    readonly property int navWidth: compactNav ? 60 : 188
    readonly property int preferredWidth: 900
    readonly property int preferredHeight: 680
    readonly property int pageIndex: Math.max(0,
        navItems.findIndex(item => item.id === Settings.page))
    readonly property bool dragActive: pageLoader.item
        ? (pageLoader.item.dragActive ?? false) : false

    implicitWidth: Math.max(320, Math.min(preferredWidth, availableWidth))
    implicitHeight: Math.max(280, Math.min(preferredHeight, availableHeight))
    focus: true

    readonly property var navItems: [
        { id: "appearance", group: "SHELL", label: "Appearance", glyph: "palette",
            title: "Appearance", description: "Theme, colors, and typography" },
        { id: "wallpaper", group: "SHELL", label: "Wallpaper", glyph: "image",
            title: "Wallpaper", description: "Desktop image and automatic rotation" },
        { id: "bar", group: "SHELL", label: "Bar", glyph: "space_dashboard",
            title: "Bar", description: "Placement, shape, behavior, and monitors" },
        { id: "modules", group: "SHELL", label: "Modules", glyph: "widgets",
            title: "Modules", description: "Choose and arrange the bar’s contents" },
        { id: "notifications", group: "SYSTEM", label: "Notifications", glyph: "notifications",
            title: "Notifications", description: "Toasts, quiet hours, and the notification center" },
        { id: "system", group: "SYSTEM", label: "System", glyph: "settings",
            title: "System", description: "Formats, night light, OSD, and storage" }
    ]

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
        if (navItems.length === 0)
            return;
        const clamped = Math.max(0, Math.min(navItems.length - 1, position));
        Settings.page = navItems[clamped].id;
        const item = navDelegate(navItems[clamped].id);
        if (item)
            item.forceActiveFocus();
    }

    function selectOffset(delta) {
        const current = navItems.findIndex(item => item.id === Settings.page);
        selectVisible(current === -1 ? 0 : current + delta);
    }

    function cancelDrag() {
        if (pageLoader.item && pageLoader.item.cancelDrag)
            pageLoader.item.cancelDrag();
    }

    // Called by IslandPopout. A module drag consumes the first Escape and an
    // open module sub-page the next; otherwise the host closes the panel.
    function handleEscape(): bool {
        if (dragActive) {
            cancelDrag();
            return true;
        }
        if (pageLoader.item && (pageLoader.item.subPageActive ?? false)) {
            pageLoader.item.closeSubPage();
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
        height: 42
        radius: Theme.rowRadius
        color: current ? Theme.accentBg : "transparent"
        border.width: activeFocus ? 1 : 0
        border.color: Theme.accent
        activeFocusOnTab: navItem.current
        Accessible.role: Accessible.PageTab
        Accessible.name: navItem.modelData.label
        Accessible.selected: navItem.current
        Accessible.onPressAction: {
            navState.pulseCenter();
            Settings.page = navItem.modelData.id;
        }
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
                root.selectVisible(root.navItems.length - 1); event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                navState.pulseCenter();
                Settings.page = modelData.id; event.accepted = true;
            }
        }

        StateLayer {
            id: navState
            anchors.fill: parent
            radius: parent.radius
            hovered: navMouse.containsMouse
            pressed: navMouse.pressed
            focused: navItem.activeFocus
            tint: navItem.current ? Theme.accent : Theme.textHi
            pressPoint: Qt.point(navMouse.mouseX, navMouse.mouseY)
        }

        Sym {
            id: navIcon
            anchors.left: parent.left
            anchors.leftMargin: root.compactNav ? 0 : 12
            anchors.verticalCenter: parent.verticalCenter
            width: root.compactNav ? parent.width : 20
            horizontalAlignment: Text.AlignHCenter
            name: navItem.modelData.glyph
            size: Theme.iconMedium
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
            width: parent.width - x - 10
            elide: Text.ElideRight
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
            id: headerCopy
            anchors.left: parent.left
            anchors.leftMargin: root.gutter
            anchors.right: headerActions.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                text: root.navItems[root.pageIndex].title
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontHeading
                font.weight: Theme.weightSemibold
                color: Theme.textHi
                width: parent.width
                elide: Text.ElideRight
            }

            Text {
                text: root.navItems[root.pageIndex].description
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: Theme.textDim
                width: parent.width
                elide: Text.ElideRight
            }
        }

        Row {
            id: headerActions
            anchors.right: parent.right
            anchors.rightMargin: root.gutter
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            SettingsAction {
                visible: Settings.sectionDirty(Settings.page)
                text: "Reset page"
                glyph: "↺"
                onTriggered: Settings.resetSection(Settings.page)
            }

            SettingsAction {
                compact: true
                text: "Close"
                glyph: "×"
                onTriggered: Settings.closePanel()
            }
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

            GroupLabel {
                text: "SHELL"
                topPad: 0
                visible: !root.compactNav
            }

            Repeater {
                id: shellRepeater
                model: root.navItems.filter(item => item.group === "SHELL")
                delegate: NavItem {}
            }

            GroupLabel {
                text: "SYSTEM"
                visible: !root.compactNav
            }

            Repeater {
                id: systemRepeater
                model: root.navItems.filter(item => item.group === "SYSTEM")
                delegate: NavItem {}
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
                compact: root.compactNav
                text: "Undo"
                glyph: "↺"
                Accessible.name: "Undo " + Settings.resetLabel + " reset"
                onTriggered: Settings.undoReset()
            }

            SettingsAction {
                visible: Settings.saveError && !Settings.undoAvailable
                height: 26
                compact: root.compactNav
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
