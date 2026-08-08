import QtQuick
import Quickshell
import "../Common"

// T3 Code bar module (design 2b): the official T3 mark (pingdotgg/t3code,
// MIT) plus a status word — sessions needing approval/input win (amber),
// then running turns, then a quiet idle mark. The mark is white while
// connected and dimmed while off/connecting. Opens the T3 popover.
Item {
    id: root

    // ---- panel wiring -----------------------------------------------------
    // Same contract as BarIcon/BarChip: one panel name drives registration and
    // the held state, against a typed host so a typo is a lint error.
    property Bar host: null
    property string panelName: ""
    property string isle: ""

    readonly property bool ownsPanel: panelName !== "" && host !== null

    // The bar assigns `host` from its slot's onLoaded, which runs after this
    // object is constructed — so registering only in Component.onCompleted
    // would run against a null host and silently never happen. Registration
    // is idempotent, so doing both is safe and covers either order.
    onOwnsPanelChanged: {
        if (ownsPanel)
            host.registerPanel(panelName, root);
    }

    Component.onCompleted: {
        if (ownsPanel)
            host.registerPanel(panelName, root);
    }

    Component.onDestruction: {
        if (ownsPanel)
            host.unregisterPanel(panelName, root);
    }

    // Registration alone only reaches the bar's hover switch, which is gated
    // on a popout already being open; the chip's own click and hover are what
    // open the first one. Driven from inside the MouseArea as BarIcon/BarChip
    // do, so a use-site onClicked cannot silently unwire the panel.
    function hoverIn() {
        if (ownsPanel)
            host.hoverOpen(panelName, isle, root);
        entered();
    }

    signal clicked()
    signal entered()
    signal exited()

    property bool held: ownsPanel && host.popoutOpen(panelName)
    property int displayMode: 2
    // False while the hosting bar is another output's or slid away by
    // auto-hide: nothing of this chip is on screen, so its pulse must not
    // drive the compositor.
    property bool barVisible: true

    readonly property bool live: T3Code.state === "connected"
    readonly property bool stressed: live && T3Code.attentionCount > 0
    readonly property bool busy: live && !stressed && T3Code.runningCount > 0
    readonly property string label: {
        if (!live)
            return T3Code.state === "connecting" ? "connecting…" : "off";
        if (T3Code.attentionCount > 0)
            return T3Code.attentionCount + " waiting";
        if (T3Code.runningCount > 0)
            return T3Code.runningCount + " running";
        if (T3Code.doneCount > 0)
            return T3Code.doneCount + " done";
        return "idle";
    }
    readonly property real detailSaving: labelText.implicitWidth + 5

    implicitHeight: Theme.chipHeight
    implicitWidth: chip.width
    anchors.verticalCenter: parent.verticalCenter

    Rectangle {
        id: chip
        height: Theme.chipHeight
        width: chipRow.implicitWidth + 12
        radius: Theme.chipRadius
        anchors.verticalCenter: parent.verticalCenter
        // The same ladder every other chip uses: transparent at rest, the
        // light fill under the pointer, the strong one while the popout is
        // open. This used to rest on hoverFill, which read as a chip stuck in
        // its hover state next to the transparent glyph buttons beside it.
        color: root.stressed ? Theme.amberBg
             : root.held ? Theme.hoverFillStrong
             : chipPointer.over ? Theme.hoverFill
             : "transparent"

        Behavior on color {
            ColorAnimation { duration: Theme.chipFadeDuration }
        }

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5

            Image {
                anchors.verticalCenter: parent.verticalCenter
                height: 9
                width: 15
                sourceSize: Qt.size(30, 18)
                fillMode: Image.PreserveAspectFit
                source: Quickshell.shellDir + "/assets/" + (root.live ? "t3.svg" : "t3-dim.svg")
            }

            // Running pulse: a quiet dot that breathes while agents work.
            Rectangle {
                id: runningDot
                property real pulseOpacity: 1
                property double pulseStartedAt: 0

                visible: root.busy
                anchors.verticalCenter: parent.verticalCenter
                width: 5
                height: 5
                radius: 3
                color: Theme.accent
                opacity: Settings.modOpts.t3.pulse ? pulseOpacity : 1

                // A slow five-pixel pulse does not benefit from driving the
                // entire Wayland surface at the monitor's 120 Hz refresh rate.
                // Thirty evenly timed samples per second remain visually
                // smooth while allowing the compositor to sleep between them.
                Timer {
                    interval: 33
                    repeat: true
                    running: root.barVisible && runningDot.visible && Settings.modOpts.t3.pulse
                    // Restarting resets the phase, so the pulse picks up
                    // cleanly from full opacity whenever the bar returns.
                    onRunningChanged: {
                        runningDot.pulseStartedAt = Date.now();
                        runningDot.pulseOpacity = 1;
                    }
                    onTriggered: {
                        const phase = ((Date.now() - runningDot.pulseStartedAt) % 1800) / 1800;
                        runningDot.pulseOpacity = 0.625 + 0.375 * Math.cos(phase * Math.PI * 2);
                    }
                }
            }

            Text {
                id: labelText
                visible: root.displayMode > 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                font.family: Theme.fontMenu
                font.pixelSize: Theme.barTextSize
                font.weight: root.stressed ? Theme.weightSemibold
                           : root.live && (T3Code.runningCount > 0 || T3Code.doneCount > 0)
                           ? Theme.weightMedium : Theme.weightRegular
                font.features: Theme.tabularNumberFeatures
                color: {
                    if (!root.live)
                        return T3Code.state === "connecting" ? Theme.textLow : Theme.textFaint;
                    if (root.stressed)
                        return Theme.amber;
                    if (T3Code.runningCount > 0 || T3Code.doneCount > 0)
                        return Theme.textMid;
                    return Theme.textLow;
                }
            }
        }

        PointerCheck {
            id: chipPointer
            host: root.host
            target: chip
            hovered: chipMouse.containsMouse
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.hoverIn()
            // A newly mapped layer surface can cost Qt the next enter event;
            // motion over the chip still re-arms the bar's hover switch.
            onPositionChanged: root.hoverIn()
            onExited: {
                if (root.ownsPanel)
                    root.host.cancelHover(root.panelName);
                root.exited();
            }
            onClicked: {
                if (root.ownsPanel)
                    root.host.togglePopout(root.panelName, root.isle, root);
                root.clicked();
            }
        }

        BarTooltip {
            check: chipPointer
            text: {
                if (T3Code.state === "unpaired")
                    return "T3 Code · not paired";
                // Off covers a refused port, a dead name, a bad certificate
                // and a rejected ticket; say which one when the transport
                // gave a reason worth repeating.
                if (!root.live)
                    return "T3 Code · " + T3Code.state
                        + (T3Code.connectionError !== ""
                           ? " · " + T3Code.connectionError : "");
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
