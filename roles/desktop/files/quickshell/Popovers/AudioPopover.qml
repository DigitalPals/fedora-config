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

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    // Default sink first, then local (ALSA) devices, then network sinks;
    // capped so the popover stays compact with many cast targets around.
    readonly property var sinks: {
        const all = Pipewire.nodes.values.filter(n => n.isSink && !n.isStream);
        const rank = n => n === Pipewire.defaultAudioSink ? 0 : (n.name || "").startsWith("alsa") ? 1 : 2;
        return all.sort((a, b) => rank(a) - rank(b)
            || (a.description || a.name).localeCompare(b.description || b.name)).slice(0, 6);
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].concat(root.sinks)
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

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            horizontalAlignment: Text.AlignHCenter
            text: root.sink && root.sink.audio && root.sink.audio.muted ? "\uf026" : "\uf028"
            font.family: Theme.fontIcon
            font.pixelSize: Theme.fontBody
            color: Theme.textMid

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (root.sink && root.sink.audio)
                        root.sink.audio.muted = !root.sink.audio.muted;
                }
            }
        }

        BlockMeter {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 84
            height: 10
            interactive: true
            value: root.sink && root.sink.audio ? root.sink.audio.volume : 0
            onMoved: v => {
                if (root.sink && root.sink.audio)
                    root.sink.audio.volume = v;
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            horizontalAlignment: Text.AlignRight
            text: root.sink && root.sink.audio ? Math.round(root.sink.audio.volume * 100) : "--"
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

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                horizontalAlignment: Text.AlignHCenter
                text: root.devicesOpen ? "\uf077" : "\uf078"
                font.family: Theme.fontIcon
                font.pixelSize: Theme.fontCaption
                color: discMouse.containsMouse ? Theme.textHi : Theme.textDim
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: root.width - 70
                text: root.sink ? (root.sink.description || root.sink.nickname || root.sink.name) : "No output device"
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
                readonly property bool isDefault: modelData === Pipewire.defaultAudioSink

                width: parent.width - 4
                x: 2
                height: Theme.rowHeight
                radius: Theme.rowRadius
                color: devMouse.containsMouse ? Theme.hoverFill : "transparent"

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 10
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        horizontalAlignment: Text.AlignHCenter
                        text: sink.isDefault ? "\uf00c" : ""
                        font.family: Theme.fontIcon
                        font.pixelSize: Theme.fontBody
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
                    onClicked: Pipewire.preferredDefaultAudioSink = sink.modelData
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
            color: root.source && root.source.audio && root.source.audio.muted ? Theme.redBg : "transparent"

            Text {
                anchors.centerIn: parent
                text: root.source && root.source.audio && root.source.audio.muted ? "\uf131" : "\uf130"
                font.family: Theme.fontIcon
                font.pixelSize: Theme.fontBody
                color: root.source && root.source.audio && root.source.audio.muted ? Theme.redText : Theme.textMid
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (root.source && root.source.audio)
                        root.source.audio.muted = !root.source.audio.muted;
                }
            }
        }

        BlockMeter {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 84
            height: 10
            interactive: true
            opacity: root.source && root.source.audio && root.source.audio.muted ? 0.45 : 1
            fillColor: root.source && root.source.audio && root.source.audio.muted ? Theme.textLow : Theme.accent
            value: root.source && root.source.audio ? root.source.audio.volume : 0
            onMoved: v => {
                if (root.source && root.source.audio)
                    root.source.audio.volume = v;
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            horizontalAlignment: Text.AlignRight
            text: root.source && root.source.audio ? Math.round(root.source.audio.volume * 100) : "--"
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSecondary
            font.weight: Theme.weightMedium
            color: root.source && root.source.audio && root.source.audio.muted ? Theme.textDim : Theme.textLow
        }
    }
}
