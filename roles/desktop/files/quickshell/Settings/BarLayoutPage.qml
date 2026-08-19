import QtQuick
import Quickshell
import "../Common"

// Bar layout page: live edge-style preview, position, floating geometry,
// behavior switches, and monitor pinning.
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
            badgeText: Settings.position + " · " + Settings.barStyle
                + (Settings.autoHide ? " · auto-hide" : "")

            Rectangle {
                id: previewSlab
                readonly property real previewGap: Settings.barStyle === "floating"
                    ? Math.max(4, Math.min(20, Settings.gap)) : 0
                x: previewGap
                y: Settings.position === "top"
                    ? previewGap
                    : parent.height - height - previewGap
                width: parent.width - previewGap * 2
                height: 17
                radius: Settings.barStyle === "floating"
                    ? Math.max(2, Math.round(Settings.barRadius * 0.5)) : 0
                color: Theme.barSurface
                opacity: Settings.autoHide ? 0.4 : 1

                Behavior on x { NumberAnimation { duration: Theme.popoutContentFadeDuration; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: Theme.popoutContentFadeDuration; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: Theme.popoutContentFadeDuration; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: Theme.popoutContentFadeDuration } }

                HugCorner {
                    visible: Settings.barStyle === "hug"
                    x: 0
                    y: Settings.position === "top" ? parent.height : -height
                    bottomCorner: Settings.position === "bottom"
                    cornerSize: 7
                    fillColor: Theme.barSurface
                }

                HugCorner {
                    visible: Settings.barStyle === "hug"
                    x: parent.width - width
                    y: Settings.position === "top" ? parent.height : -height
                    rightCorner: true
                    bottomCorner: Settings.position === "bottom"
                    cornerSize: 7
                    fillColor: Theme.barSurface
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    width: 9
                    height: 5
                    radius: 2.5
                    color: Theme.barAccent
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
                            color: Theme.barDotDim
                        }
                    }
                }
            }
        }

        PickerRow {
            width: parent.width
            label: "Position"
            settingKey: "position"
            model: [{ value: "top", label: "Top" }, { value: "bottom", label: "Bottom" }]
        }

        PickerRow {
            width: parent.width
            label: "Style"
            settingKey: "barStyle"
            caption: "edge treatment"
            captionMono: false
            model: [
                { value: "hug", label: "Hug" },
                { value: "floating", label: "Floating" },
                { value: "attached", label: "Attached" }
            ]
        }

        SliderRow {
            width: parent.width
            label: "Edge gap"
            settingKey: "gap"
            min: 4
            max: 20
            step: 1
            unit: "px"
            dimmed: Settings.barStyle !== "floating"
        }

        SectionHeader {
            label: "BEHAVIOR"
        }

        SwitchRow {
            width: parent.width
            label: "Auto-hide"
            settingKey: "autoHide"
            description: "Bar slides away when idle — hover the screen edge to reveal"
        }

        SwitchRow {
            width: parent.width
            label: "Reserve space"
            settingKey: "exclusive"
            description: "Exclusive zone — tiled windows stop at the bar"
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
