pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Pipewire
import "../Common"
import "../Common/AudioHelpers.js" as AudioHelpers

Surface {
    id: root

    // Right-island popouts run a touch wider (design t5).
    implicitWidth: Theme.popWideWidth

    property bool networkDevicesOpen: AudioHelpers.isNetworkSink(Audio.outputSink)

    readonly property var allSinks: {
        // While the tuning exists, offering its physical downstream sink would
        // let the user bypass processing. Headphones, Bluetooth, HDMI, and USB
        // remain ordinary choices and never enter the filter graph.
        return Pipewire.nodes.values.filter(n => n.isSink && !n.isStream
            && !(Audio.tuningPresent && n === Audio.speakerSink));
    }
    readonly property var localSinks: AudioHelpers.localSinks(allSinks, Audio.outputSink)
    readonly property var networkSinks: AudioHelpers.networkSinks(allSinks, Audio.outputSink)

    component SinkRow: Rectangle {
        id: sinkRow

        required property var sinkNode
        readonly property bool isDefault: sinkNode === Audio.outputSink

        width: root.width - root.padding * 2 - 4
        x: 2
        height: Theme.rowHeight
        radius: Theme.rowRadius
        color: sinkMouse.containsMouse || activeFocus ? Theme.hoverFill : "transparent"
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: "Use " + AudioHelpers.sinkLabel(sinkNode)
        Accessible.checked: isDefault
        Accessible.onPressAction: Audio.setDefaultSink(sinkNode)
        border.width: activeFocus ? 1 : 0
        border.color: Theme.accent

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                Audio.setDefaultSink(sinkRow.sinkNode);
                event.accepted = true;
            }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 10
            spacing: 10

            Sym {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                horizontalAlignment: Text.AlignHCenter
                name: sinkRow.isDefault ? "check" : ""
                size: Theme.fontBody
                color: Theme.accent
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: root.width - root.padding * 2 - 70
                text: AudioHelpers.sinkLabel(sinkRow.sinkNode)
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontBody
                color: sinkRow.isDefault ? Theme.textHi : Theme.textLow
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: sinkMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Audio.setDefaultSink(sinkRow.sinkNode)
        }
    }

    SectionLabel {
        text: "OUTPUT"
    }

    // Output volume
    Row {
        id: outputRow

        width: parent.width
        leftPadding: 10
        rightPadding: 10
        topPadding: 6
        bottomPadding: 6
        spacing: 10

        Sym {
            id: outputGlyph

            anchors.verticalCenter: parent.verticalCenter
            width: 18
            horizontalAlignment: Text.AlignHCenter
            name: Audio.muted ? "volume_off" : "volume_up"
            size: Theme.fontBody
            color: Theme.textMid

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Audio.toggleMuted();
                }
            }
        }

        BlockMeter {
            anchors.verticalCenter: parent.verticalCenter
            width: outputRow.width - outputRow.leftPadding - outputRow.rightPadding
                - outputGlyph.width - outputValue.width - outputRow.spacing * 2
            height: 10
            interactive: true
            value: Audio.level
            onMoved: v => {
                Audio.setVolume(v);
            }
        }

        Text {
            id: outputValue

            anchors.verticalCenter: parent.verticalCenter
            width: 26
            horizontalAlignment: Text.AlignRight
            text: Audio.ready ? Audio.volume : "--"
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSecondary
            font.weight: Theme.weightMedium
            color: Theme.textLow
        }
    }

    SectionLabel {
        text: "LOCAL DEVICES"
    }

    Column {
        width: parent.width

        Repeater {
            model: root.localSinks

            delegate: SinkRow {
                required property var modelData
                sinkNode: modelData
            }
        }
    }

    Rectangle {
        visible: root.networkSinks.length > 0
        width: parent.width - 4
        x: 2
        height: Theme.rowHeight
        radius: Theme.rowRadius
        color: networkMouse.containsMouse || activeFocus ? Theme.hoverFill : "transparent"
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: (root.networkDevicesOpen ? "Hide" : "Show")
            + " network and AirPlay outputs"
        Accessible.onPressAction: root.networkDevicesOpen = !root.networkDevicesOpen
        border.width: activeFocus ? 1 : 0
        border.color: Theme.accent

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                root.networkDevicesOpen = !root.networkDevicesOpen;
                event.accepted = true;
            }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 10
            spacing: 10

            Sym {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                horizontalAlignment: Text.AlignHCenter
                name: root.networkDevicesOpen ? "expand_less" : "expand_more"
                size: Theme.fontCaption
                color: networkMouse.containsMouse ? Theme.textHi : Theme.textDim
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Network / AirPlay (" + root.networkSinks.length + ")"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontBody
                color: networkMouse.containsMouse ? Theme.textMid : Theme.textLow
            }
        }

        MouseArea {
            id: networkMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.networkDevicesOpen = !root.networkDevicesOpen
        }
    }

    Column {
        visible: root.networkDevicesOpen
        width: parent.width

        Repeater {
            model: root.networkSinks

            delegate: SinkRow {
                required property var modelData
                sinkNode: modelData
            }
        }
    }

    HDivider {}

    SectionLabel {
        text: "INPUT"
    }

    // Mic
    Row {
        id: inputRow

        width: parent.width
        leftPadding: 10
        rightPadding: 10
        topPadding: 6
        bottomPadding: 10
        spacing: 10

        Rectangle {
            id: inputMute

            anchors.verticalCenter: parent.verticalCenter
            width: Theme.controlHeight
            height: Theme.controlHeight
            radius: 6
            color: Audio.sourceMuted ? Theme.redBg : "transparent"

            Sym {
                anchors.centerIn: parent
                name: Audio.sourceMuted ? "mic_off" : "mic"
                size: Theme.fontBody
                color: Audio.sourceMuted ? Theme.redText : Theme.textMid
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Audio.toggleSourceMuted();
                }
            }
        }

        BlockMeter {
            anchors.verticalCenter: parent.verticalCenter
            width: inputRow.width - inputRow.leftPadding - inputRow.rightPadding
                - inputMute.width - inputValue.width - inputRow.spacing * 2
            height: 10
            interactive: true
            opacity: Audio.sourceMuted ? 0.45 : 1
            fillColor: Audio.sourceMuted ? Theme.textLow : Theme.accent
            value: Audio.sourceLevel
            onMoved: v => {
                Audio.setSourceVolume(v);
            }
        }

        Text {
            id: inputValue

            anchors.verticalCenter: parent.verticalCenter
            width: 26
            horizontalAlignment: Text.AlignRight
            text: Audio.sourceReady ? Audio.sourceVolume : "--"
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSecondary
            font.weight: Theme.weightMedium
            color: Audio.sourceMuted ? Theme.textDim : Theme.textLow
        }
    }
}
