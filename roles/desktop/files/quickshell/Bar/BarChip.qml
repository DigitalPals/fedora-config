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

    // Padding either side of the content. 7 matches BarIcon's optical inset
    // for text-led chips; the weather chip runs one tighter because its
    // leading glyph already carries side bearing.
    property real hPadding: 7
    property real spacing: 6
    // The module's popout is expanded below it (design t5).
    property bool held: false
    property string tooltip: ""
    property int tooltipAlign: 0

    readonly property bool hovered: mouse.containsMouse

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
        onEntered: root.entered()
        // A newly mapped layer surface can cost Qt the next enter event;
        // motion over the chip still re-arms the bar's hover switch.
        onPositionChanged: root.entered()
        onExited: root.exited()
        onClicked: root.clicked()
    }

    BarTooltip {
        hovered: mouse.containsMouse
        text: root.tooltip
        align: root.tooltipAlign
        y: root.height + 6
        x: align < 0 ? 0 : align > 0 ? root.width - width : (root.width - width) / 2
    }
}
