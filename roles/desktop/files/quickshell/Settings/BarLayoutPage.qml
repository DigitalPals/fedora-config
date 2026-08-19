import QtQuick
import Quickshell
import "../Common"

// The persisted page id remains `bar`; only the visible name and grouping
// change. Floating-only geometry stays stored while its controls are hidden.
SettingsPage {
    id: page

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 12

        SettingsGroup {
            width: parent.width
            title: "Preview"

            PreviewStrip {
                width: parent.width
                height: 108
                badgeText: Settings.position + " · " + Settings.barStyle
                    + (Settings.autoHide ? " · auto-hide" : "")

                Rectangle {
                    readonly property real previewGap: Settings.barStyle === "floating"
                        ? Math.max(4, Math.min(20, Settings.gap)) : 0
                    x: previewGap
                    y: Settings.position === "top"
                        ? previewGap : parent.height - height - previewGap
                    width: parent.width - previewGap * 2
                    height: Math.max(17, Math.round(Settings.barHeight * 0.42))
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
                        width: 9; height: 5; radius: 2.5
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
                                width: 5; height: 5; radius: 2.5
                                color: Theme.barDotDim
                            }
                        }
                    }
                }
            }
        }

        SettingsGroup {
            width: parent.width
            title: "Placement"
            dirty: Settings.position !== Settings.defaults.position
            onResetRequested: Settings.resetKeys(["position"], "Bar placement")

            PickerRow {
                width: parent.width
                label: "Position"
                settingKey: "position"
                model: [
                    { value: "top", label: "Top" },
                    { value: "bottom", label: "Bottom" }
                ]
            }
        }

        SettingsGroup {
            width: parent.width
            title: "Shape"
            dirty: Settings.barStyle !== Settings.defaults.barStyle
                || Settings.gap !== Settings.defaults.gap
                || Settings.barHeight !== Settings.defaults.barHeight
                || Settings.barRadius !== Settings.defaults.barRadius
            onResetRequested: Settings.resetKeys(["barStyle", "gap", "barHeight", "barRadius"], "Bar shape")

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
                label: "Height"
                settingKey: "barHeight"
                min: 28; max: 60; step: 1; unit: "px"
            }

            PickerRow {
                width: parent.width
                label: "Height presets"
                settingKey: "barHeight"
                model: [
                    { value: 38, label: "Compact 38" },
                    { value: 46, label: "Default 46" },
                    { value: 54, label: "Roomy 54" }
                ]
            }

            Revealer {
                id: floatingReveal
                width: parent.width
                reveal: Settings.barStyle === "floating"

                Column {
                    width: floatingReveal.width
                    spacing: 4
                    SliderRow {
                        width: parent.width
                        label: "Edge gap"
                        settingKey: "gap"
                        min: 4; max: 20; step: 1; unit: "px"
                    }
                    SliderRow {
                        width: parent.width
                        label: "Corner radius"
                        settingKey: "barRadius"
                        min: 0; max: 30; step: 1; unit: "px"
                    }
                }
            }
        }

        SettingsGroup {
            width: parent.width
            title: "Behavior"
            dirty: Settings.autoHide !== Settings.defaults.autoHide
                || Settings.exclusive !== Settings.defaults.exclusive
            onResetRequested: Settings.resetKeys(["autoHide", "exclusive"], "Bar behavior")

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
        }

        SettingsGroup {
            width: parent.width
            title: "Monitors"
            dirty: Settings.monitor !== Settings.defaults.monitor
            onResetRequested: Settings.resetKeys(["monitor"], "Bar monitor")

            PickerRow {
                width: parent.width
                label: "Monitor"
                settingKey: "monitor"
                mono: true
                model: [{ value: "All", label: "Follow focus" }].concat(
                    Quickshell.screens.map(s => ({ value: s.name, label: s.name })))
            }
        }
    }
}
