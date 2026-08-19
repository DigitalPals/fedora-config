import QtQuick
import "../Common"
import "../Common/Format.js" as Format

// The design's filled slider: a pill-radius tile whose accent gradient fill
// is the value readout. The glyph sits inside the track on the left — as a
// plain mark, or as a button when `glyphIsButton` (the volume mute) — and
// the percentage label on the right. Drag anywhere on the track to set the
// value; the wheel nudges it.
Rectangle {
    id: root

    // 0..1.
    property real value: 0
    property string glyph
    property bool glyphIsButton: false
    property string label: Math.round(Format.clamp01(value) * 100) + "%"
    property bool ready: true
    property string accessibleName: "Slider"
    signal moved(real value)
    signal glyphClicked

    // The glyph occupies the first control-height-wide lane. A non-zero fill
    // narrower than that turns into a detached vertical lozenge and leaves
    // the glyph floating beside it. Keep the leading fill circular until the
    // actual value grows past that lane; zero still has no fill at all.
    readonly property real fillExtent: {
        const exact = Format.clamp01(value) * width;
        return exact <= 0 ? 0 : Math.min(width, Math.max(height, exact));
    }

    height: Theme.controlHeight
    radius: height / 2
    color: Theme.tile
    opacity: ready ? 1 : 0.4

    Accessible.role: Accessible.Slider
    Accessible.name: accessibleName
    Accessible.description: root.label

    Behavior on color {
        ColorAnimation { duration: Theme.surfaceDuration }
    }

    Rectangle {
        width: root.fillExtent
        height: parent.height
        radius: parent.radius

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.accentSoft }
            GradientStop { position: 1; color: Theme.accent }
        }

        Behavior on width {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.ready
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => root.moved(Format.clamp01(mouse.x / root.width))
        onPositionChanged: mouse => {
            if (pressed)
                root.moved(Format.clamp01(mouse.x / root.width));
        }
        onWheel: wheel => root.moved(Format.clamp01(root.value + (wheel.angleDelta.y / 120) * 0.05))
    }

    Sym {
        visible: !root.glyphIsButton
        x: 15
        anchors.verticalCenter: parent.verticalCenter
        name: root.glyph
        size: 18
        fill: 1
        color: Theme.textHi
    }

    Rectangle {
        visible: root.glyphIsButton
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 30
        height: 30
        radius: 15
        color: glyphMouse.containsMouse ? Theme.chipHover : "transparent"

        Sym {
            anchors.centerIn: parent
            name: root.glyph
            size: 18
            fill: 1
            color: Theme.textHi
        }

        MouseArea {
            id: glyphMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.glyphClicked()
        }
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 15
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontTiny
        font.weight: Theme.weightHeavy
        color: Theme.textHi
    }
}
