import QtQuick
import Quickshell
import "../Common"

// T3 Code bar module: one chip with the "t3" mark and the state of the
// remote agent sessions — sessions needing approval/input win (amber),
// then running turns, then a quiet idle mark. Opens the T3 popover.
Item {
    id: root

    signal clicked()
    signal entered()
    signal exited()

    property bool held: false
    property int displayMode: 2

    readonly property bool live: T3Code.state === "connected"
    readonly property bool stressed: live && T3Code.attentionCount > 0
    readonly property string label: {
        if (!live)
            return T3Code.state === "connecting" ? "…" : "off";
        if (T3Code.attentionCount > 0)
            return T3Code.attentionCount + " waiting";
        if (T3Code.runningCount > 0)
            return T3Code.runningCount + " running";
        if (T3Code.doneCount > 0)
            return T3Code.doneCount + " done";
        return "idle";
    }

    implicitHeight: 22
    implicitWidth: chip.width
    anchors.verticalCenter: parent.verticalCenter

    Rectangle {
        id: chip
        height: 22
        width: chipRow.implicitWidth + 14
        radius: Theme.chipRadius
        anchors.verticalCenter: parent.verticalCenter
        color: root.stressed ? Theme.amberBg
             : root.held || chipMouse.containsMouse ? Theme.hoverFillStrong
             : Theme.hoverFill

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "t3"
                font.family: Theme.fontMono
                font.pixelSize: 11
                font.weight: 700
                color: !root.live ? Theme.textFaint
                     : root.stressed ? Theme.amber
                     : T3Code.runningCount > 0 ? Theme.accent
                     : Theme.textMid
            }

            // Running pulse: a quiet dot that breathes while agents work.
            Rectangle {
                visible: root.live && T3Code.runningCount > 0 && !root.stressed
                anchors.verticalCenter: parent.verticalCenter
                width: 5
                height: 5
                radius: 3
                color: Theme.accent

                SequentialAnimation on opacity {
                    running: visible
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.25; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.25; to: 1; duration: 900; easing.type: Easing.InOutSine }
                }
            }

            Text {
                visible: root.displayMode > 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                font.family: Theme.fontSans
                font.pixelSize: 11
                font.weight: root.stressed ? 600 : 500
                color: !root.live ? Theme.textFaint
                     : root.stressed ? Theme.amber
                     : Theme.textMid
            }
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            onEntered: root.entered()
            onExited: root.exited()
            onClicked: root.clicked()
        }

        BarTooltip {
            hovered: chipMouse.containsMouse
            text: {
                if (T3Code.state === "unpaired")
                    return "T3 Code · not paired";
                if (!root.live)
                    return "T3 Code · " + T3Code.state;
                const host = T3Code.environmentLabel !== "" ? T3Code.environmentLabel : "sessions";
                return "T3 Code · " + host + " · " + T3Code.runningCount + " running, "
                    + T3Code.attentionCount + " waiting";
            }
            align: 1
            y: chip.height + 6
            x: chip.width - width
        }
    }
}
