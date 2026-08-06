import QtQuick
import "../Common"

// Connected center-island settings surface. The host supplies the usable
// output envelope before measuring implicit size.
FocusScope {
    id: root

    property real availableWidth: 720
    property real availableHeight: 560
    readonly property bool compactNav: availableWidth < 680
    readonly property int headerHeight: 44
    readonly property int footerHeight: 36
    readonly property int gutter: 12
    readonly property int navWidth: compactNav ? 52 : 156
    readonly property int preferredWidth: 720
    readonly property int preferredHeight: 560
    readonly property int pageIndex: Math.max(0,
        navItems.findIndex(item => item.id === Settings.page))
    readonly property bool dragActive: pageLoader.item
        ? (pageLoader.item.dragActive ?? false) : false

    implicitWidth: Math.max(320, Math.min(preferredWidth, availableWidth))
    implicitHeight: Math.max(280, Math.min(preferredHeight, availableHeight))
    focus: true

    readonly property var navItems: [
        { id: "appearance", label: "Appearance", glyph: "",
            title: "Appearance", description: "Shape, typography, and shell accent" },
        { id: "wallpaper", label: "Wallpaper", glyph: "",
            title: "Wallpaper", description: "Desktop image and automatic rotation" },
        { id: "bar", label: "Bar layout", glyph: "",
            title: "Bar layout", description: "Position, spacing, and monitor behavior" },
        { id: "modules", label: "Modules", glyph: "",
            title: "Modules", description: "Choose and arrange the bar’s contents" },
        { id: "system", label: "System", glyph: "",
            title: "System", description: "Formats, night light, OSD, and storage" }
    ]

    function selectIndex(index) {
        const clamped = Math.max(0, Math.min(navItems.length - 1, index));
        Settings.page = navItems[clamped].id;
        navRepeater.itemAt(clamped).forceActiveFocus();
    }

    function cancelDrag() {
        if (pageLoader.item && pageLoader.item.cancelDrag)
            pageLoader.item.cancelDrag();
    }

    // Called by IslandPopout. A module drag consumes the first Escape.
    function handleEscape(): bool {
        if (!dragActive)
            return false;
        cancelDrag();
        return true;
    }

    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.popoutContentFadeDuration; easing.type: Easing.OutCubic }
    }
    Behavior on implicitHeight {
        NumberAnimation { duration: Theme.popoutContentFadeDuration; easing.type: Easing.OutCubic }
    }

    component NavItem: Rectangle {
        id: navItem
        required property var modelData
        required property int index
        readonly property bool current: Settings.page === modelData.id

        width: navColumn.width
        height: 38
        radius: Theme.rowRadius
        color: current ? Theme.accentBg
            : navMouse.pressed ? Theme.hoverFillStrong
            : navMouse.containsMouse || activeFocus ? Theme.hoverFill : "transparent"
        border.width: activeFocus ? 1 : 0
        border.color: Theme.accent
        activeFocusOnTab: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
                root.selectIndex(index - 1); event.accepted = true;
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
                root.selectIndex(index + 1); event.accepted = true;
            } else if (event.key === Qt.Key_Home) {
                root.selectIndex(0); event.accepted = true;
            } else if (event.key === Qt.Key_End) {
                root.selectIndex(root.navItems.length - 1); event.accepted = true;
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
            width: root.compactNav ? parent.width : 24
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
        height: parent.height - root.headerHeight - root.footerHeight - 2

        Column {
            id: navColumn
            x: root.gutter / 2
            y: root.gutter
            width: root.navWidth - root.gutter
            spacing: 3

            Repeater {
                id: navRepeater
                model: root.navItems
                delegate: NavItem {}
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
                case "system": return systemPage;
                default: return appearancePage;
                }
            }
        }

        Component { id: appearancePage; AppearancePage {} }
        Component { id: wallpaperPage; WallpaperPage {} }
        Component { id: barPage; BarLayoutPage {} }
        Component { id: modulesPage; ModulesPage {} }
        Component { id: systemPage; SystemPage {} }
    }

    Rectangle {
        y: parent.height - root.footerHeight - 1
        width: parent.width
        height: 1
        color: Theme.hairlineSoft
    }

    Item {
        y: parent.height - root.footerHeight
        width: parent.width
        height: root.footerHeight

        Row {
            anchors.left: parent.left
            anchors.leftMargin: root.gutter
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 6; height: 6; radius: 3
                color: Settings.saveError ? Theme.red
                    : Settings.savePending ? Theme.amber : Theme.connected
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Settings.saveError ? "Could not save"
                    : Settings.savePending ? "Saving changes…" : "Saved · changes apply live"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: Settings.saveError ? Theme.redText : Theme.textFaint
            }
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: root.gutter
            anchors.verticalCenter: parent.verticalCenter
            visible: root.width >= 560
            text: "shell-settings.json"
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontCaption
            color: Theme.textFaint
        }
    }
}
