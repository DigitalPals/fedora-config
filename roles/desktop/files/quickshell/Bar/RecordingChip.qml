import QtQuick
import "../Common"

// The recording indicator, and the button that stops it.
//
// It pulses, which nothing else in the bar does. That is deliberate and
// bounded: the T3 running dot was made static because it is permanent
// furniture, whereas this chip only exists while a capture is running and its
// whole job is to be impossible to forget about.
BarChip {
    id: root

    visible: Recorder.active
    restFill: Theme.redBg
    hoverFill: Theme.red
    hPadding: 12
    spacing: 6
    tooltip: "Stop recording" + (Recorder.outputFile !== ""
        ? " · " + Recorder.outputFile.split("/").pop() : "")
    tooltipAlign: 1
    onClicked: Recorder.toggle()

    readonly property color ink: hovered ? Theme.textOnAccent : Theme.redText

    Rectangle {
        id: pulse
        anchors.verticalCenter: parent.verticalCenter
        width: 7
        height: 7
        radius: 3.5
        color: root.ink

        SequentialAnimation on opacity {
            running: root.visible
            loops: Animation.Infinite
            alwaysRunToEnd: false

            NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Recorder.elapsedLabel
        font.family: Theme.fontMenu
        font.pixelSize: Theme.barLabelSize
        font.weight: Theme.weightHeavy
        font.features: Theme.tabularNumberFeatures
        color: root.ink

        Behavior on color {
            ColorAnimation { duration: Theme.chipFadeDuration }
        }
    }
}
