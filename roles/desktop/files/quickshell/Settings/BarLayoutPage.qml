import QtQuick
import Quickshell
import "../Common"

// Bar layout page (design v2): live position/floating preview, position,
// floating + edge gap, behavior switches, and monitor pinning.
SettingsPage {
    id: page

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 10

        PreviewStrip {
            width: parent.width
            height: 105
            badgeText: Settings.position + " · " + (Settings.floating ? "floating" : "attached")
                + (Settings.autoHide ? " · auto-hide" : "")

            Rectangle {
                readonly property real previewGap: Settings.floating
                    ? Math.max(4, Math.min(20, Settings.gap)) : 0
                x: previewGap
                y: Settings.position === "top"
                    ? previewGap
                    : parent.height - height - previewGap
                width: parent.width - previewGap * 2
                height: 17
                radius: Settings.floating ? Math.max(2, Math.round(Settings.barRadius * 0.5)) : 0
                color: Theme.barBg
                opacity: Settings.autoHide ? 0.4 : 1

                Behavior on x { NumberAnimation { duration: Theme.popoutContentFadeDuration; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: Theme.popoutContentFadeDuration; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: Theme.popoutContentFadeDuration; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: Theme.popoutContentFadeDuration } }

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    width: 9
                    height: 5
                    radius: 2.5
                    color: Theme.accent
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            width: 5
                            height: 5
                            radius: 2.5
                            color: Theme.dotDim
                        }
                    }
                }
            }
        }

        PickerRow {
            width: parent.width
            label: "Position"
            model: [{ value: "top", label: "Top" }, { value: "bottom", label: "Bottom" }]
            current: Settings.position
            dirty: Settings.position !== Settings.defaults.position
            onPicked: value => Settings.set("position", value)
            onResetRequested: Settings.resetKeys(["position"])
        }

        SwitchRow {
            width: parent.width
            label: "Floating"
            description: "Detached island with rounded corners; off = edge-to-edge"
            checked: Settings.floating
            dirty: Settings.floating !== Settings.defaults.floating
            onToggled: value => Settings.set("floating", value)
            onResetRequested: Settings.resetKeys(["floating"])
        }

        SliderRow {
            width: parent.width
            label: "Edge gap"
            min: 4
            max: 20
            step: 1
            value: Settings.gap
            unit: "px"
            dimmed: !Settings.floating
            dirty: Settings.gap !== Settings.defaults.gap
            onMoved: value => Settings.set("gap", value)
            onResetRequested: Settings.resetKeys(["gap"])
        }

        SectionHeader {
            label: "BEHAVIOR"
        }

        SwitchRow {
            width: parent.width
            label: "Auto-hide"
            description: "Bar slides away when idle — hover the screen edge to reveal"
            checked: Settings.autoHide
            dirty: Settings.autoHide !== Settings.defaults.autoHide
            onToggled: value => Settings.set("autoHide", value)
            onResetRequested: Settings.resetKeys(["autoHide"])
        }

        SwitchRow {
            width: parent.width
            label: "Reserve space"
            description: "Exclusive zone — tiled windows stop at the bar"
            checked: Settings.exclusive
            dirty: Settings.exclusive !== Settings.defaults.exclusive
            onToggled: value => Settings.set("exclusive", value)
            onResetRequested: Settings.resetKeys(["exclusive"])
        }

        SectionHeader {
            label: "MONITORS"
            dirty: Settings.monitor !== Settings.defaults.monitor
            onResetRequested: Settings.resetKeys(["monitor"])
        }

        PillRow {
            width: parent.width
            mono: true
            model: [{ value: "All", label: "Follow focus" }].concat(
                Quickshell.screens.map(s => ({ value: s.name, label: s.name })))
            current: Settings.monitor
            onPicked: value => Settings.set("monitor", value)
        }
    }
}
