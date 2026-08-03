import QtQuick
import "../Common"

// Small keyboard-friendly picker used by the T3 composer. Its menu opens
// upward so the fixed composer does not grow beyond the bounded popover.
Item {
    id: root

    property string label: ""
    property string value: ""
    property color valueColor: Theme.textMid
    property var options: []
    property bool expanded: false
    property bool openUpward: true
    property int menuRows: 7
    signal selected(string value)

    implicitHeight: 34
    z: expanded ? 100 : 0
    activeFocusOnTab: enabled && visible

    function optionId(option) {
        if (!option)
            return "";
        return String(option.id ?? option.instanceId ?? option.slug ?? option.value ?? "");
    }

    function optionLabel(option) {
        if (!option)
            return "";
        return String(option.label ?? option.displayName ?? option.name ?? option.shortName
            ?? optionId(option));
    }

    function selectedLabel() {
        const found = (Array.isArray(options) ? options : [])
            .find(option => optionId(option) === value);
        return found ? optionLabel(found) : (value !== "" ? value : "Unavailable");
    }

    function move(delta) {
        const choices = (Array.isArray(options) ? options : [])
            .filter(option => option.disabled !== true);
        if (choices.length === 0)
            return;
        let at = choices.findIndex(option => optionId(option) === value);
        at = (at + delta + choices.length) % choices.length;
        selected(optionId(choices[at]));
    }

    Keys.onPressed: event => {
        if (!root.enabled)
            return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            root.expanded = !root.expanded;
            event.accepted = true;
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
            root.move(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
            root.move(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.expanded) {
            root.expanded = false;
            event.accepted = true;
        }
    }

    Rectangle {
        id: button

        anchors.fill: parent
        radius: 6
        color: pickerMouse.containsMouse && root.enabled ? Theme.hoverFillStrong : Theme.hoverFill
        opacity: root.enabled ? 1 : 0.45
        border.width: root.activeFocus || root.expanded ? 1 : 0
        border.color: Theme.accent

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.right: chevron.left
            anchors.rightMargin: 5
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
                visible: root.label !== ""
                width: parent.width
                text: root.label.toUpperCase()
                elide: Text.ElideRight
                font.family: Theme.fontSans
                font.pixelSize: 9
                font.weight: 600
                font.letterSpacing: 0.5
                color: Theme.textDim
            }

            Text {
                width: parent.width
                text: root.selectedLabel()
                elide: Text.ElideRight
                font.family: Theme.fontSans
                font.pixelSize: 11
                color: root.valueColor
            }
        }

        Text {
            id: chevron
            anchors.right: parent.right
            anchors.rightMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            text: root.expanded ? "▴" : "▾"
            font.family: Theme.fontMono
            font.pixelSize: 9
            color: Theme.textDim
        }

        MouseArea {
            id: pickerMouse
            anchors.fill: parent
            enabled: root.enabled
            hoverEnabled: true
            onClicked: {
                root.forceActiveFocus();
                root.expanded = !root.expanded;
            }
        }
    }

    Rectangle {
        id: menu

        z: 1000
        visible: root.expanded && root.enabled
        anchors.left: parent.left
        anchors.right: parent.right
        y: root.openUpward ? -height - 4 : root.height + 4
        height: Math.min(root.menuRows, root.options.length) * 30 + 8
        radius: 8
        color: "#1b1c22"
        border.width: 1
        border.color: Theme.popBorder
        clip: true

        Flickable {
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
                        height: 30
                        radius: 5
                        color: chosen ? Theme.accentBg
                            : choiceMouse.containsMouse ? Theme.hoverFillStrong : "transparent"
                        opacity: modelData.disabled === true ? 0.35 : 1

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 7
                            anchors.right: mark.left
                            anchors.rightMargin: 5
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.optionLabel(choice.modelData)
                            elide: Text.ElideRight
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            color: choice.chosen ? Theme.textHi : Theme.textMid
                        }

                        Text {
                            id: mark
                            anchors.right: parent.right
                            anchors.rightMargin: 7
                            anchors.verticalCenter: parent.verticalCenter
                            text: choice.chosen ? "✓" : ""
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            color: Theme.accent
                        }

                        MouseArea {
                            id: choiceMouse
                            anchors.fill: parent
                            enabled: choice.modelData.disabled !== true
                            hoverEnabled: true
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
    }
}
