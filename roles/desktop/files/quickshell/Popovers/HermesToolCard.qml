import QtQuick
import "../Common"

// One live or recent Hermes tool call. It stays compact at rest and exposes
// command/path/error detail without letting verbose tool output take over chat.
Rectangle {
    id: root

    required property var tool
    property bool expanded: false

    readonly property bool running: !tool.terminal
        && ["running", "started", "pending", "working"].indexOf(tool.status) >= 0
    readonly property bool failed: tool.status === "error" || tool.status === "failed"
    readonly property string statusIcon: failed ? "error"
        : running ? "progress_activity"
            : tool.status === "interrupted" || tool.status === "cancelled"
                ? "cancel" : "check_circle"
    readonly property color statusColor: failed ? HermesTheme.red
        : running ? HermesTheme.accent : HermesTheme.success

    width: parent ? parent.width : 0
    height: toolColumn.implicitHeight + 12
    radius: HermesTheme.rowRadius
    color: failed ? HermesTheme.redSoft
        : running ? HermesTheme.accentSubtle : "transparent"
    border.width: failed || running || activeFocus ? 1 : 0
    border.color: activeFocus ? HermesTheme.focus
        : failed ? HermesTheme.redBorder : HermesTheme.border
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: (tool.label || tool.name) + ", " + tool.status
    Accessible.onPressAction: expanded = !expanded

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            root.expanded = !root.expanded;
            event.accepted = true;
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.expanded = !root.expanded
    }

    Column {
        id: toolColumn
        x: 7
        y: 6
        width: parent.width - 14
        spacing: 4

        Item {
            width: parent.width
            height: 20

            Sym {
                id: statusGlyph
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                name: root.statusIcon
                size: Theme.iconSmall
                symWeight: 460
                color: root.statusColor

                RotationAnimation on rotation {
                    running: root.running && !Theme.reducedMotion
                    from: 0
                    to: 360
                    loops: Animation.Infinite
                    duration: 950
                }
            }

            Text {
                anchors.left: statusGlyph.right
                anchors.leftMargin: 7
                anchors.right: toolStatus.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.tool.label || root.tool.name
                elide: Text.ElideRight
                font.family: HermesTheme.fontUi
                font.pixelSize: Theme.fontCaption
                font.weight: Theme.weightSemibold
                color: HermesTheme.textSecondary
            }

            Text {
                id: toolStatus
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.running ? "running…" : root.tool.status
                font.family: HermesTheme.fontUi
                font.pixelSize: Theme.fontMicro
                color: root.statusColor
            }
        }

        Text {
            visible: root.expanded && text !== ""
            width: parent.width
            text: root.tool.error || root.tool.detail
            textFormat: Text.PlainText
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: 8
            elide: Text.ElideRight
            font.family: HermesTheme.fontMono
            font.pixelSize: Theme.fontMicro
            color: root.failed ? HermesTheme.red : HermesTheme.textFaint
        }
    }
}
