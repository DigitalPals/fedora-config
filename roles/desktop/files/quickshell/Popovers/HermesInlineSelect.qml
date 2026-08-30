pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

Item {
    id: root

    property string text: ""
    property string symbol: ""
    property string value: ""
    property var options: []
    property bool expanded: false
    property bool openUpward: true
    property int menuRows: 8
    property int menuWidth: 176
    property real maxWidth: 1000
    readonly property int popupHeight:
        Math.min(menuRows, options.length) * Theme.pickerRowHeight + 8
    readonly property Item popupItem: menu
    signal selected(string value)

    implicitWidth: trigger.implicitWidth
    implicitHeight: trigger.implicitHeight
    z: expanded ? 100 : 0

    function optionId(option) {
        return option ? String(option.id ?? option.value ?? "") : "";
    }

    function optionLabel(option) {
        return option ? String(option.label ?? option.name ?? optionId(option)) : "";
    }

    function selectedLabel() {
        const found = (Array.isArray(options) ? options : [])
            .find(option => optionId(option) === value);
        return found ? optionLabel(found) : text;
    }

    function containsPickerPoint(item, x, y) {
        if (!item)
            return false;
        const point = root.mapFromItem(item, x, y);
        const inButton = point.x >= 0 && point.x <= root.width
            && point.y >= 0 && point.y <= root.height;
        const inMenu = menu.visible && point.x >= menu.x
            && point.x <= menu.x + menu.width && point.y >= menu.y
            && point.y <= menu.y + menu.height;
        return inButton || inMenu;
    }

    onEnabledChanged: if (!enabled) expanded = false
    onVisibleChanged: if (!visible) expanded = false

    TapHandler {
        enabled: root.expanded && root.enabled && root.visible
        margin: root.Window.window
            ? Math.max(root.Window.window.width, root.Window.window.height) : 0
        onTapped: eventPoint => {
            if (!root.containsPickerPoint(root, eventPoint.position.x,
                    eventPoint.position.y))
                root.expanded = false;
        }
    }

    HermesBarControl {
        id: trigger
        anchors.fill: parent
        text: root.selectedLabel()
        accessibleDescription: root.text
        symbol: root.symbol
        maxWidth: root.maxWidth
        active: root.expanded
        enabled: root.enabled
        onTriggered: root.expanded = !root.expanded
    }

    Rectangle {
        id: menu
        z: 1000
        visible: root.expanded && root.enabled
        x: 0
        y: root.openUpward ? -height - 6 : root.height + 6
        width: Math.max(root.menuWidth, root.width)
        height: root.popupHeight
        radius: HermesTheme.panelRadius
        color: HermesTheme.overlay
        border.width: 1
        border.color: HermesTheme.borderStrong
        clip: true

        Flickable {
            id: menuFlick
            anchors.fill: parent
            anchors.margins: 4
            contentWidth: width
            contentHeight: choices.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            clip: true

            Column {
                id: choices
                width: parent.width

                Repeater {
                    model: root.options

                    delegate: Rectangle {
                        id: choice
                        required property var modelData
                        readonly property string choiceId: root.optionId(modelData)
                        readonly property bool chosen: choiceId === root.value
                        width: parent.width
                        height: Theme.pickerRowHeight
                        radius: HermesTheme.controlRadius
                        color: chosen ? Theme.chip
                            : choiceMouse.containsMouse ? HermesTheme.hoverStrong
                                : "transparent"

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.right: mark.left
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.optionLabel(choice.modelData)
                            elide: Text.ElideRight
                            font.family: HermesTheme.fontUi
                            font.pixelSize: Theme.fontSecondary
                            color: choice.chosen ? HermesTheme.textPrimary
                                : HermesTheme.textSecondary
                        }

                        Sym {
                            id: mark
                            visible: choice.chosen
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            name: "check"
                            size: Theme.iconSmall
                            symWeight: 550
                            color: HermesTheme.accent
                        }

                        MouseArea {
                            id: choiceMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selected(choice.choiceId);
                                root.expanded = false;
                                root.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }

        ScrollChrome {
            anchors.fill: parent
            anchors.margins: 4
            target: menuFlick
            fadeSize: 16
            edgeColor: HermesTheme.overlay
            thumbColor: HermesTheme.accent
        }
    }
}
