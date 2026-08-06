import QtQuick
import "../Common"

// Shell settings chrome (design v2): header, left nav, page loader, footer.
// Fixed-size surface — pages lay out inside a 440px content viewport.
Item {
    id: root

    readonly property int headerHeight: 40
    readonly property int bodyHeight: 440
    readonly property int footerHeight: 34
    readonly property int navWidth: 150
    readonly property int contentPadding: 14

    implicitWidth: 680
    implicitHeight: headerHeight + 1 + bodyHeight + 1 + footerHeight

    readonly property bool dragActive: pageLoader.item ? (pageLoader.item.dragActive ?? false) : false

    function cancelDrag() {
        if (pageLoader.item && pageLoader.item.cancelDrag)
            pageLoader.item.cancelDrag();
    }

    readonly property var navItems: [
        { id: "wallpaper", label: "Wallpaper" },
        { id: "appearance", label: "Appearance" },
        { id: "bar", label: "Bar layout" },
        { id: "modules", label: "Modules" },
        { id: "system", label: "System" }
    ]

    component NavItem: Rectangle {
        id: navItem

        required property var modelData
        readonly property bool current: Settings.page === modelData.id

        width: parent.width
        height: 30
        radius: 7
        color: navItem.current ? Theme.activeFill
            : navMouse.containsMouse ? Theme.hoverFill : "transparent"

        Rectangle {
            id: navDot
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: 3
            color: navItem.current ? Theme.accent : Theme.textFaint
        }

        Text {
            anchors.left: navDot.right
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: navItem.modelData.label
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.weightMedium
            color: navItem.current ? Theme.textHi : Theme.textLow
        }

        MouseArea {
            id: navMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: Settings.page = navItem.modelData.id
        }
    }

    // ---- header --------------------------------------------------------
    Item {
        id: header
        width: parent.width
        height: root.headerHeight

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "Shell settings"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontSecondary
            font.weight: Theme.weightSemibold
            color: Theme.textHi
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "shell-settings.json"
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontCaption
                color: Theme.textFaint
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 22
                radius: 6
                color: closeMouse.containsMouse ? Theme.hoverFillStrong : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontSecondary
                    color: closeMouse.containsMouse ? Theme.textHi : Theme.textDim
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Settings.closeWindow()
                }
            }
        }
    }

    Rectangle {
        y: root.headerHeight
        width: parent.width
        height: 1
        color: Theme.hairlineSoft
    }

    // ---- body: nav + content -------------------------------------------
    Item {
        id: body
        y: root.headerHeight + 1
        width: parent.width
        height: root.bodyHeight

        Column {
            id: nav
            x: 8
            y: 8
            width: root.navWidth - 16
            spacing: 2

            Repeater {
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
            x: root.navWidth + 1 + root.contentPadding
            y: root.contentPadding
            width: parent.width - root.navWidth - 1 - root.contentPadding * 2
            height: parent.height - root.contentPadding * 2
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

        Component { id: wallpaperPage; WallpaperPage {} }
        Component { id: appearancePage; AppearancePage {} }
        Component { id: barPage; BarLayoutPage {} }
        Component { id: modulesPage; ModulesPage {} }
        Component { id: systemPage; SystemPage {} }
    }

    Rectangle {
        y: root.headerHeight + 1 + root.bodyHeight
        width: parent.width
        height: 1
        color: Theme.hairlineSoft
    }

    // ---- footer --------------------------------------------------------
    Item {
        id: footer
        y: root.headerHeight + 2 + root.bodyHeight
        width: parent.width
        height: root.footerHeight

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "Changes apply live — no restart"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: Theme.textFaint
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "Reset section"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: resetMouse.containsMouse ? Theme.textHi : Theme.textFaint

            MouseArea {
                id: resetMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: Settings.resetSection(Settings.page)
            }
        }
    }
}
