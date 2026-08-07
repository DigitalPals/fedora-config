import QtQuick
import "../Common"

// A content chip in a bar cluster: the same hover/held pill BarIcon draws for
// glyph modules, but wrapping arbitrary content instead of glyph + label.
// The two are deliberately the same shape — same height, radius, fill states
// and fade — so a chip and an icon sitting next to each other agree.
//
// Like BarIcon, this knows nothing about the bar: it reports pointer events as
// signals and takes `held` as a property, so the module wires it to
// barWindow.hoverOpen/togglePopout at the use site. Content binds its own
// colours off `held` and `hovered`.
Rectangle {
    id: root

    default property alias content: inner.data

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

    // Padding either side of the content. 7 matches BarIcon's optical inset
    // for text-led chips; the weather chip runs one tighter because its
    // leading glyph already carries side bearing.
    property real hPadding: 7
    property real spacing: 6
    // The module's popout is expanded below it (design t5).
    property bool held: ownsPanel && host.popoutOpen(panelName)
    property string tooltip: ""
    property int tooltipAlign: 0

    readonly property bool hovered: mouse.containsMouse

    function hoverIn() {
        if (ownsPanel)
            host.hoverOpen(panelName, isle, anchorItem);
        entered();
    }

    signal clicked()
    signal entered()
    signal exited()

    implicitHeight: Theme.chipHeight
    implicitWidth: inner.implicitWidth + hPadding * 2
    radius: Theme.chipRadius
    color: held ? Theme.hoverFillStrong : mouse.containsMouse ? Theme.hoverFill : "transparent"
    anchors.verticalCenter: parent.verticalCenter

    Behavior on color {
        ColorAnimation { duration: Theme.chipFadeDuration }
    }

    Row {
        id: inner
        anchors.centerIn: parent
        spacing: root.spacing
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
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
                root.host.togglePopout(root.panelName, root.isle, root.anchorItem);
            root.clicked();
        }
    }

    BarTooltip {
        host: root.host
        hovered: mouse.containsMouse
        text: root.tooltip
        align: root.tooltipAlign
        y: root.height + 6
        x: align < 0 ? 0 : align > 0 ? root.width - width : (root.width - width) / 2
    }
}
