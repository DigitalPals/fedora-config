pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Pipewire
import "../Common"

Surface {
    id: root

    // Right-island popouts run a touch wider (design t5).
    implicitWidth: Theme.popWideWidth

    // Output device list stays collapsed behind a disclosure row.
    property bool devicesOpen: false

    // Default sink first, then local (ALSA) devices, then network sinks;
    // capped so the popover stays compact with many cast targets around.
    readonly property var sinks: {
        // While the tuning exists, offering its physical downstream sink would
        // let the user bypass processing. Headphones, Bluetooth, HDMI, and USB
        // remain ordinary choices and never enter the filter graph.
        const all = Pipewire.nodes.values.filter(n => n.isSink && !n.isStream
            && !(Audio.tuningPresent && n === Audio.speakerSink));
        const rank = n => n === Audio.outputSink ? 0 : (n.name || "").startsWith("alsa") ? 1 : 2;
        return all.sort((a, b) => rank(a) - rank(b)
            || (a.description || a.name).localeCompare(b.description || b.name)).slice(0, 6);
    }

    // Only the extra devices: Common/Audio.qml already tracks the two
    // defaults for the whole shell, and this list is worth binding only
    // while the picker is on screen.
    PwObjectTracker {
        objects: root.sinks
    }

    SectionLabel {
        text: "OUTPUT"
    }

    // Output volume
    Row {
        width: parent.width
        leftPadding: 10
        rightPadding: 10
        topPadding: 6
        bottomPadding: 6
        spacing: 10

        Sym {
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
            width: parent.width - 84
            height: 10
            interactive: true
            value: Audio.level
            onMoved: v => {
                Audio.setVolume(v);
            }
        }

        Text {
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

    // Device disclosure: the current output, click to reveal the list.
    Rectangle {
        width: parent.width - 4
        x: 2
        height: Theme.rowHeight
        radius: Theme.rowRadius
        color: discMouse.containsMouse ? Theme.hoverFill : "transparent"

        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 10
            spacing: 10

            Sym {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                horizontalAlignment: Text.AlignHCenter
                name: root.devicesOpen ? "expand_less" : "expand_more"
                size: Theme.fontCaption
                color: discMouse.containsMouse ? Theme.textHi : Theme.textDim
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: root.width - 70
                text: Audio.outputSink ? (Audio.outputSink.description || Audio.outputSink.nickname || Audio.outputSink.name) : "No output device"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontBody
                color: discMouse.containsMouse ? Theme.textMid : Theme.textLow
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: discMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.devicesOpen = !root.devicesOpen
        }
    }

    // Output devices (collapsed until the disclosure row is opened)
    Column {
        visible: root.devicesOpen
        width: parent.width

        Repeater {
            model: root.sinks

            delegate: Rectangle {
                id: sink

                required property var modelData
                readonly property bool isDefault: modelData === Audio.outputSink

                width: parent.width - 4
                x: 2
                height: Theme.rowHeight
                radius: Theme.rowRadius
                color: devMouse.containsMouse ? Theme.hoverFill : "transparent"

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 10
                    spacing: 10

                    Sym {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        horizontalAlignment: Text.AlignHCenter
                        name: sink.isDefault ? "check" : ""
                        size: Theme.fontBody
                        color: Theme.accent
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.width - 70
                        text: sink.modelData.description || sink.modelData.nickname || sink.modelData.name
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontBody
                        color: sink.isDefault ? Theme.textHi : Theme.textLow
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: devMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Audio.setDefaultSink(sink.modelData)
                }
            }
        }
    }

    HDivider {}

    SectionLabel {
        text: "INPUT"
    }

    // Mic
    Row {
        width: parent.width
        leftPadding: 10
        rightPadding: 10
        topPadding: 6
        bottomPadding: 10
        spacing: 10

        Rectangle {
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
            width: parent.width - 84
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
