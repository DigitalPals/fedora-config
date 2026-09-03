pragma ComponentBehavior: Bound
import QtQuick
import "../../Common"
import "../../Common/PanelRegistryData.js" as PanelRegistry

// The drawer's tab strip. The current tab carries its icon and label on a
// lit segment; the others compress to icons sharing the remaining width, so
// the strip holds one row at every drawer width. Selecting a tab reopens the
// popout under that tab's canonical panel name — same name space as the bar
// glyphs and IPC — which keeps the surface exactly where it is.
Rectangle {
    id: root

    property string current: "overview"

    readonly property var tabs: [
        { tab: "overview", glyph: "dashboard", label: "Overview" },
        { tab: "sound", glyph: "volume_down", label: "Sound" },
        { tab: "network", glyph: "wifi", label: "Network" },
        { tab: "power", glyph: "battery_5_bar", label: "Power", rotate: true },
        { tab: "notifications", glyph: "notifications", label: "Notifications" },
        { tab: "usage", glyph: "insights", label: "Usage" }
    ]

    height: 36
    radius: 9
    color: Theme.chip

    Row {
        anchors.fill: parent
        anchors.margins: 3
        spacing: 2

        Repeater {
            model: root.tabs

            delegate: Rectangle {
                id: segment

                required property var modelData
                readonly property bool on: modelData.tab === root.current
                // The lit segment takes its natural width; the rest split
                // what is left evenly.
                readonly property real restWidth: {
                    let lit = 0;
                    for (const t of root.tabs) {
                        if (t.tab === root.current)
                            lit = 24 + 6 + labelMetrics.width;
                    }
                    return (parent.width - lit - 2 * (root.tabs.length - 1))
                        / (root.tabs.length - 1);
                }

                TextMetrics {
                    id: labelMetrics
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontCaption
                    font.weight: Theme.weightSemibold
                    text: segment.modelData.label
                }

                width: on ? 24 + 6 + labelMetrics.width : Math.max(24, restWidth)
                height: parent.height
                radius: 7
                color: on ? Theme.chipHover : "transparent"

                Behavior on width {
                    NumberAnimation {
                        duration: Theme.expandDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.springCurve
                    }
                }

                Behavior on color {
                    ColorAnimation { duration: Theme.chipFadeDuration }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16

                        Sym {
                            anchors.centerIn: parent
                            name: segment.modelData.glyph
                            size: 16
                            fill: segment.on ? 1 : 0
                            rotation: segment.modelData.rotate === true ? 90 : 0
                            color: segment.on ? Theme.textHi : Theme.textFaint
                        }
                    }

                    Text {
                        visible: segment.on
                        anchors.verticalCenter: parent.verticalCenter
                        text: segment.modelData.label
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontCaption
                        font.weight: Theme.weightSemibold
                        color: Theme.textHi
                    }
                }

                // Unread mark on the resting Notifications tab, in the same
                // place the bar's bell wears its dot.
                Rectangle {
                    visible: segment.modelData.tab === "notifications"
                        && !segment.on && Notifs.count > 0
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: 7
                    anchors.topMargin: 6
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.accent
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    hovered: segmentMouse.containsMouse && !segment.on
                    pressed: segmentMouse.pressed
                    tint: Theme.textHi
                    pressPoint: Qt.point(segmentMouse.mouseX, segmentMouse.mouseY)
                }

                MouseArea {
                    id: segmentMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (segment.on)
                            return;
                        const name = PanelRegistry.nameForTab(segment.modelData.tab);
                        if (name !== "")
                            Popouts.openPanel(name, "right");
                    }
                }

                Accessible.role: Accessible.PageTab
                Accessible.name: segment.modelData.label
            }
        }
    }
}
