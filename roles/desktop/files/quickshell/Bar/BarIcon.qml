import QtQuick
import "../Common"
import "../Common/LayoutHelpers.js" as LayoutHelpers

// A glyph button in a bar cluster: nerd-font icon, optional compact label,
// optional accent (active) or red (alert) pill state.
Rectangle {
    id: root

    // ---- panel wiring -----------------------------------------------------
    // Setting panelName makes this the bar's anchor for that popout and drives
    // registration, the held state, hover-switching and click from the one
    // name. `host` is typed rather than duck-typed, so a typo in any of those
    // calls is a lint error naming the member, not a silent no-op.
    //
    // `isle` is the column the module actually sits in — the user can move
    // modules between columns, so it is assigned by the bar's ModuleSlot and
    // is not the registry's default island.
    property Bar host: null
    property string panelName: ""
    property string isle: ""

    // The item whose rectangle the popout hangs under. Defaults to this one;
    // the bell overrides it with its wrapper, whose height is the full bar
    // row rather than the icon's, so the popout keeps its exact anchor.
    property Item anchorItem: root

    readonly property bool ownsPanel: panelName !== "" && host !== null

    // The bar assigns `host` from its slot's onLoaded, which runs after this
    // object is constructed — so registering only in Component.onCompleted
    // would run against a null host and silently never happen. Registration
    // is idempotent, so doing both is safe and covers either order.
    onOwnsPanelChanged: {
        if (ownsPanel)
            host.registerPanel(panelName, anchorItem);
    }

    Component.onCompleted: {
        if (ownsPanel)
            host.registerPanel(panelName, anchorItem);
    }

    Component.onDestruction: {
        if (ownsPanel)
            host.unregisterPanel(panelName, anchorItem);
    }

    property string glyph
    property real glyphSize: Theme.barIconSize
    // Fixed column for the glyph. The right cluster is right-anchored, so
    // a module that changes width slides every module beside it: pin the
    // width for icons that differ between states. 0 sizes to the glyph.
    property real glyphWidth: 0
    property string label: ""
    property bool compact: false
    property real labelSize: Theme.barTextSize
    property bool active: false
    // Subtle open-state: the module's popout is expanded below it (t5).
    property bool held: ownsPanel && host.popoutOpen(panelName)
    property bool alert: false
    property color idleColor: Theme.icon
    property color hoverColor: Theme.textHi
    property int hPadding: 6
    property string tooltip: ""
    property int tooltipAlign: 0
    signal clicked(real mouseX)
    signal middleClicked
    signal wheeled(int steps)
    signal entered
    signal exited

    property real wheelAccumulator: 0
    readonly property real detailSaving: label === "" ? 0 : labelText.implicitWidth + 4

    readonly property color fg: active ? Theme.accentFg : alert ? Theme.redText : held || mouse.hovered ? hoverColor : idleColor

    implicitHeight: Theme.chipHeight
    implicitWidth: inner.implicitWidth + hPadding * 2
    radius: Theme.chipRadius
    color: active ? Theme.accent : alert ? Theme.redBg : held ? Theme.hoverFillStrong : mouse.hovered ? Theme.hoverFill : "transparent"
    anchors.verticalCenter: parent.verticalCenter

    Behavior on color {
        ColorAnimation { duration: Theme.chipFadeDuration }
    }

    Row {
        id: inner
        anchors.centerIn: parent
        spacing: 4

        // The column is pinned on the wrapper, never on the Text: these
        // glyphs' ink overflows their advance box, so giving the Text an
        // explicit width shifts what it draws.
        Item {
            visible: root.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: root.glyphWidth > 0 ? root.glyphWidth : glyphText.implicitWidth
            height: glyphText.implicitHeight

            Text {
                id: glyphText
                anchors.centerIn: parent
                text: root.glyph
                font.family: Theme.fontIcon
                font.pixelSize: root.glyphSize
                color: root.fg

                Behavior on color {
                    ColorAnimation { duration: Theme.chipFadeDuration }
                }
            }
        }

        Text {
            id: labelText
            visible: root.label !== "" && !root.compact
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            font.family: Theme.fontMenu
            font.pixelSize: root.labelSize
            font.weight: root.alert ? Theme.weightSemibold : Theme.weightMedium
            font.features: Theme.tabularNumberFeatures
            color: root.alert ? Theme.redText : root.fg

            Behavior on color {
                ColorAnimation { duration: Theme.chipFadeDuration }
            }
        }
    }

    MouseArea {
        id: mouse
        property bool hovered: false
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onEntered: {
            hovered = true;
            if (root.ownsPanel)
                root.host.hoverOpen(root.panelName, root.isle, root.anchorItem);
            root.entered();
        }
        // A newly mapped layer surface can cost Qt the next enter event;
        // motion over the icon still re-arms the bar's hover switch.
        onPositionChanged: {
            if (root.ownsPanel)
                root.host.hoverOpen(root.panelName, root.isle, root.anchorItem);
            root.entered();
        }
        onExited: {
            hovered = false;
            if (root.ownsPanel)
                root.host.cancelHover(root.panelName);
            root.exited();
        }
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                root.middleClicked();
                return;
            }
            if (root.ownsPanel)
                root.host.togglePopout(root.panelName, root.isle, root.anchorItem);
            root.clicked(mouse.x);
        }
        onWheel: wheel => {
            const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y
                : wheel.pixelDelta.y * 8;
            const result = LayoutHelpers.accumulateWheel(root.wheelAccumulator, delta, 120);
            root.wheelAccumulator = result.accumulator;
            if (result.steps !== 0)
                root.wheeled(result.steps);
            wheel.accepted = true;
        }
    }

    BarTooltip {
        host: root.host
        hovered: mouse.hovered
        text: root.tooltip
        align: root.tooltipAlign
        y: root.height + 6
        x: align < 0 ? 0 : align > 0 ? root.width - width : (root.width - width) / 2
    }
}
