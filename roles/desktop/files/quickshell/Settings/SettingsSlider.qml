import QtQuick
import "../Common"

// Stepped min/max slider in the HSlider drawing language: 4px track, 10px
// knob. gradientTrack renders the night-light warmth ramp with no fill.
Item {
    id: root

    property real value: 0
    property real min: 0
    property real max: 1
    property real step: 1
    property bool dimmed: false
    property bool gradientTrack: false
    signal moved(real value)

    height: 28
    activeFocusOnTab: !dimmed

    readonly property real ratio: Math.max(0, Math.min(1, (value - min) / (max - min)))

    function apply(x) {
        let v = min + (x / width) * (max - min);
        v = Math.round(v / step) * step;
        v = Math.max(min, Math.min(max, v));
        if (v !== value)
            moved(v);
    }

    function applyValue(next) {
        const clamped = Math.max(min, Math.min(max,
            Math.round(next / step) * step));
        if (clamped !== value)
            moved(clamped);
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Down)
            applyValue(value - step);
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Up)
            applyValue(value + step);
        else if (event.key === Qt.Key_PageDown)
            applyValue(value - step * 10);
        else if (event.key === Qt.Key_PageUp)
            applyValue(value + step * 10);
        else if (event.key === Qt.Key_Home)
            applyValue(min);
        else if (event.key === Qt.Key_End)
            applyValue(max);
        else
            return;
        event.accepted = true;
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: 2
        color: root.gradientTrack ? "transparent" : Qt.rgba(1, 1, 1, 0.08)
        opacity: root.dimmed ? 0.45 : 1
        gradient: root.gradientTrack ? warmGradient : null

        Gradient {
            id: warmGradient
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#ff8c3c" }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.08) }
        }

        Rectangle {
            visible: !root.gradientTrack
            width: root.ratio * parent.width
            height: parent.height
            radius: 2
            color: root.dimmed ? Theme.textLow : Theme.accent
        }
    }

    Rectangle {
        visible: !root.dimmed
        x: Math.round(root.ratio * (parent.width - width))
        anchors.verticalCenter: parent.verticalCenter
        width: 10
        height: 10
        radius: 5
        color: Theme.textHi
        border.width: root.activeFocus ? 2 : 0
        border.color: Theme.accent
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.dimmed
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => root.apply(mouse.x)
        onPositionChanged: mouse => {
            if (pressed)
                root.apply(mouse.x);
        }
    }
}
