import QtQuick
import QtQuick.Effects
import Quickshell
import "../Common"

// T3 Code chip: the official T3 mark (pingdotgg/t3code, MIT), a live dot while
// agents are working, and a status word. Sessions needing approval or input
// win (amber), then running/background-monitoring work, then a quiet idle
// mark. The mark is white while connected and dimmed while off or connecting.
BarChip {
    id: root

    property int displayMode: 2

    readonly property bool live: T3Code.state === "connected"
    readonly property bool stressed: live && T3Code.attentionCount > 0
    readonly property bool busy: live && !stressed
        && (T3Code.runningCount > 0 || T3Code.monitoringCount > 0)
    readonly property string label: {
        if (!live)
            return T3Code.state === "connecting" ? "connecting…" : "off";
        if (T3Code.attentionCount > 0)
            return T3Code.attentionCount + " waiting";
        if (T3Code.runningCount > 0)
            return T3Code.runningCount + " running";
        if (T3Code.monitoringCount > 0)
            return T3Code.monitoringCount + " monitoring";
        if (T3Code.doneCount > 0)
            return T3Code.doneCount + " done";
        return "idle";
    }
    readonly property real detailSaving: labelText.visible
        ? labelText.implicitWidth + spacing : 0

    shape: "inner"
    hPadding: 9
    spacing: 6
    // Attention is the one state that colours the chip itself: a session
    // waiting on the user is the only thing here worth interrupting for.
    restFill: stressed ? Theme.amberBg : "transparent"
    tooltipAlign: 1
    tooltip: {
        if (T3Code.state === "unpaired")
            return "T3 Code · not paired";
        // Off covers a refused port, a dead name, a bad certificate and a
        // rejected ticket; say which one when the transport gave a reason
        // worth repeating.
        if (!root.live)
            return "T3 Code · " + T3Code.state
                + (T3Code.connectionError !== ""
                    ? " · " + T3Code.connectionError : "");
        const environment = T3Code.environmentLabel !== ""
            ? T3Code.environmentLabel : "sessions";
        return "T3 Code · " + environment + " · " + T3Code.runningCount + " running, "
            + (T3Code.monitoringCount > 0
                ? T3Code.monitoringCount + " monitoring, " : "")
            + T3Code.attentionCount + " waiting";
    }

    Image {
        anchors.verticalCenter: parent.verticalCenter
        // PreserveAspectFit, so the box is a bound rather than a shape: the
        // 5:3 mark draws 15x9 inside it.
        height: 9
        width: 15
        sourceSize: Qt.size(30, 18)
        source: Quickshell.shellDir + "/assets/" + (root.live ? "t3.svg" : "t3-dim.svg")
        opacity: 0.92
    }

    // Live work: a lit dot with its own bloom, deliberately static. A pulse
    // here would animate a permanent fixture of the bar.
    Item {
        anchors.verticalCenter: parent.verticalCenter
        width: root.busy ? 5 : 0
        height: 5
        opacity: root.busy ? 1 : 0

        Behavior on width {
            NumberAnimation {
                duration: Theme.expandDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.springCurve
            }
        }

        Behavior on opacity {
            NumberAnimation { duration: Theme.chipFadeDuration }
        }

        RectangularShadow {
            anchors.fill: dot
            radius: dot.radius
            blur: 6
            spread: 0
            color: Theme.accentGlow
        }

        Rectangle {
            id: dot
            width: 5
            height: 5
            radius: 2.5
            color: Theme.accent
        }
    }

    Text {
        id: labelText
        visible: root.displayMode > 0
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        font.family: Theme.fontMenu
        font.pixelSize: Theme.barLabelSize
        font.weight: root.stressed ? Theme.weightHeavy : Theme.weightBold
        font.features: Theme.tabularNumberFeatures
        color: {
            if (!root.live)
                return T3Code.state === "connecting" ? Theme.textLow : Theme.textFaint;
            if (root.stressed)
                return Theme.amber;
            if (T3Code.runningCount > 0 || T3Code.monitoringCount > 0
                    || T3Code.doneCount > 0)
                return Theme.textMid;
            return Theme.textLow;
        }

        Behavior on color {
            ColorAnimation { duration: Theme.chipFadeDuration }
        }
    }
}
