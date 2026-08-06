import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "Common"
import "Popovers"

// Volume / brightness OSD (design t3, shape 3a): a bottom-center pill —
// icon · blocked meter · mono % — on the overlay layer, no focus steal.
// The meter is the shared BlockMeter and fills block-by-block; mute goes
// red; the scroll wheel on the pill adjusts the value directly.
PanelWindow {
    id: root

    // Stay mapped through the fade-out; unmap once the pill is gone.
    visible: Osd.active || pill.opacity > 0.001
    screen: Screens.focused
    // Placement follows Shell settings; when pill and bar share an edge the
    // margin clears the bar zone instead of hugging the screen edge.
    readonly property bool atTop: Settings.osd === "top"
    readonly property int barClearance: Theme.barTopMargin + Theme.barHeight + 12
    readonly property bool sharesBarScreen: Screens.hasBar(root.screen)
    anchors {
        top: atTop
        bottom: !atTop
    }
    margins {
        top: atTop && Settings.position === "top" && sharesBarScreen ? barClearance : 12
        bottom: !atTop && Settings.position === "bottom" && sharesBarScreen ? barClearance : 12
    }
    // Breathing room around the pill for the drop shadow and exit slide.
    readonly property int pad: 48
    implicitWidth: pill.implicitWidth + pad * 2
    implicitHeight: pill.implicitHeight + pad * 2
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Pointer input only over the pill; everything else falls through.
    mask: Region {
        item: pill
    }

    readonly property var audio: Osd.sink && Osd.sink.audio ? Osd.sink.audio : null
    readonly property bool volumeKind: Osd.kind === "volume"
    readonly property bool muted: volumeKind && audio !== null && audio.muted
    readonly property real value: volumeKind
        ? (audio ? audio.volume : 0)
        : Math.max(0, SysInfo.brightness) / 100

    // Smooth the level, then snap the meter to whole blocks below so the
    // fill advances block-by-block rather than sliding.
    property real shown: value

    Behavior on shown {
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    RectangularShadow {
        anchors.fill: pill
        opacity: pill.opacity
        radius: pill.radius
        blur: 32
        spread: 0
        offset.y: 12
        color: Qt.rgba(0, 0, 0, 0.5)
    }

    Rectangle {
        id: pill

        x: root.pad
        y: root.pad + (Osd.active ? 0 : root.atTop ? -10 : 10)
        opacity: Osd.active ? 1 : 0
        implicitWidth: row.implicitWidth + 28
        implicitHeight: 40
        radius: 12
        color: Theme.popBg
        border.width: 1
        border.color: root.muted ? Theme.redBorder : Theme.popBorder

        Behavior on opacity {
            NumberAnimation {
                duration: 180
            }
        }

        Behavior on y {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        Row {
            id: row
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 11

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                horizontalAlignment: Text.AlignHCenter
                text: root.volumeKind
                    ? (root.muted || root.value === 0 ? "" : root.value < 0.5 ? "" : "")
                    : ""
                font.family: Theme.fontIcon
                font.pixelSize: 14
                color: root.muted ? Theme.redText : Theme.textHi
            }

            BlockMeter {
                anchors.verticalCenter: parent.verticalCenter
                width: 160
                height: 8
                fillColor: root.muted ? Qt.rgba(232 / 255, 131 / 255, 122 / 255, 0.45) : Theme.accent
                value: Math.round(root.shown * width / (blockWidth + gap)) * (blockWidth + gap) / width
            }

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 16

                Text {
                    id: pct
                    visible: !root.muted
                    anchors.right: unit.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.volumeKind
                        ? Math.round(root.value * 100)
                        : (SysInfo.brightness >= 0 ? SysInfo.brightness : "--")
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                    font.weight: 600
                    color: Theme.textHi
                }

                Text {
                    id: unit
                    visible: !root.muted
                    anchors.right: parent.right
                    anchors.baseline: pct.baseline
                    text: "%"
                    font.family: Theme.fontMono
                    font.pixelSize: 9
                    color: Theme.textLow
                }

                Text {
                    visible: root.muted
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "MUTE"
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                    font.weight: 600
                    color: Theme.redText
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            onWheel: wheel => {
                const steps = wheel.angleDelta.y / 120;
                if (root.volumeKind) {
                    if (root.audio)
                        root.audio.volume = Math.max(0, Math.min(1, root.audio.volume + steps * 0.05));
                } else {
                    SysInfo.setBrightness(SysInfo.brightness + steps * 5);
                    Osd.show("brightness");
                }
            }
        }
    }
}
