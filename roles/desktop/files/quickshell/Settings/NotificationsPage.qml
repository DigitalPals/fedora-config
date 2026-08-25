import QtQuick
import Quickshell
import "../Common"
import "../Common/SettingsHelpers.js" as SettingsHelpers

SettingsPage {
    id: page

    readonly property var quietRange: SettingsHelpers.quietRange(Settings.notifQuiet,
        Settings.notifQuietStart, Settings.notifQuietEnd)
    readonly property int footnotePad: width < Theme.settingsNarrowWidth ? 0
        : Theme.settingsLabelWidth + 10
    property real previewProgress: 1

    function sendTest() {
        Quickshell.execDetached(["notify-send", "-a", "Shell settings",
            "-i", "preferences-system-notifications", "Test notification",
            "Toasts use your current position, duration, and style settings."]);
    }

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
                height: 126
                badgeText: Settings.notifPosition.replace("-", " ") + " · "
                    + Settings.notifDuration + " s · " + Settings.notifDensity

                Item {
                    width: parent.width / 0.72
                    height: parent.height / 0.72
                    scale: 0.72
                    transformOrigin: Item.TopLeft

                    Rectangle {
                        id: miniBar
                        x: 14
                        y: Settings.position === "top" ? 8 : parent.height - height - 8
                        width: parent.width - 28
                        height: 18
                        radius: 5
                        color: Theme.barSurface
                        border.width: 1
                        border.color: Theme.barStroke
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Rectangle { width: 9; height: 4; radius: 2; color: Theme.barWsCurrent }
                            Rectangle { width: 4; height: 4; radius: 2; color: Theme.barWsOccupied }
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Repeater {
                                model: 3
                                delegate: Rectangle { width: 4; height: 4; radius: 2; color: Theme.barWsEmpty }
                            }
                        }
                    }

                    Rectangle {
                        id: miniToast
                        readonly property bool onTop: Settings.notifPosition.indexOf("top") === 0
                        readonly property bool onLeft: Settings.notifPosition.indexOf("left") !== -1
                        readonly property int pad: Settings.notifDensity === "compact" ? 7
                            : Settings.notifDensity === "roomy" ? 13 : 9
                        width: Math.min(276, parent.width - 28)
                        height: miniContent.implicitHeight + pad * 2
                        x: onLeft ? 14 : parent.width - width - 14
                        y: onTop
                            ? (Settings.position === "top" ? miniBar.y + miniBar.height + 7 : 7)
                            : (Settings.position === "bottom" ? miniBar.y - height - 7
                                : parent.height - height - 7)
                        radius: Theme.cardRadius
                        color: Theme.panelSurface
                        border.width: 1
                        border.color: Theme.popBorder

                        Row {
                            id: miniContent
                            x: miniToast.pad + 2
                            y: miniToast.pad
                            width: parent.width - (miniToast.pad + 2) * 2
                            spacing: 7
                            Rectangle {
                                id: miniIcon
                                visible: Settings.notifIcons
                                width: 28; height: 28
                                radius: 9
                                color: Theme.chip
                                border.width: 1
                                border.color: Theme.hairlineSoft

                                Image {
                                    anchors.centerIn: parent
                                    width: 19; height: 19
                                    source: "../assets/whatsapp.svg"
                                    sourceSize: Qt.size(19, 19)
                                    asynchronous: true
                                }
                            }
                            Column {
                                width: miniContent.width - (miniIcon.visible
                                    ? miniIcon.width + miniContent.spacing : 0)
                                spacing: 2
                                Item {
                                    width: parent.width
                                    height: Math.max(miniApp.implicitHeight, miniTime.implicitHeight)
                                    Text {
                                        id: miniApp
                                        anchors.left: parent.left
                                        width: Math.max(0, parent.width - miniTime.width - 6)
                                        text: "WhatsApp"
                                        font.family: Theme.fontMenu
                                        font.pixelSize: Theme.fontTiny
                                        font.weight: Theme.weightMedium
                                        color: Theme.textMid
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        id: miniTime
                                        anchors.right: parent.right
                                        text: "now"
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontCaption
                                        color: Theme.textDim
                                    }
                                }
                                Text {
                                    width: parent.width
                                    text: "Sarah Jansen"
                                    font.family: Theme.fontMenu
                                    font.pixelSize: Theme.fontCaption
                                    font.weight: Theme.weightSemibold
                                    color: Theme.textHi
                                    elide: Text.ElideRight
                                }
                                Text {
                                    visible: Settings.notifBodyLines > 0
                                    width: parent.width
                                    text: "Sure — see you at 12:30 tomorrow then!"
                                    font.family: Theme.fontMenu
                                    font.pixelSize: Theme.fontCaption
                                    color: Theme.icon
                                    wrapMode: Text.Wrap
                                    maximumLineCount: Settings.notifBodyLines
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        Rectangle {
                            visible: Settings.notifProgress
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: miniToast.pad
                            anchors.rightMargin: miniToast.pad
                            anchors.bottomMargin: miniToast.pad / 2
                            height: 2
                            radius: 1
                            color: Theme.activeFill
                            Rectangle {
                                height: parent.height
                                width: parent.width * page.previewProgress
                                radius: 1
                                color: Theme.accent
                            }
                        }
                    }
                }
            }
        }

        SettingsGroup {
            width: parent.width
            title: "Behavior"
            dirty: Settings.notifDnd !== Settings.defaults.notifDnd
                || Settings.notifQuiet !== Settings.defaults.notifQuiet
                || Settings.notifQuietStart !== Settings.defaults.notifQuietStart
                || Settings.notifQuietEnd !== Settings.defaults.notifQuietEnd
                || Settings.notifDuration !== Settings.defaults.notifDuration
                || Settings.notifPosition !== Settings.defaults.notifPosition
            onResetRequested: Settings.resetKeys(["notifDnd", "notifQuiet",
                "notifQuietStart", "notifQuietEnd", "notifDuration", "notifPosition"],
                "Notification behavior")

            SwitchRow {
                width: parent.width
                label: "Do Not Disturb"
                settingKey: "notifDnd"
                description: "Silence toasts — everything still lands in the center"
            }
            PickerRow {
                width: parent.width
                label: "Quiet hours"
                settingKey: "notifQuiet"
                resetKeys: ["notifQuiet", "notifQuietStart", "notifQuietEnd"]
                model: [
                    { value: "off", label: "Off" },
                    { value: "nights", label: "Nights" },
                    { value: "custom", label: "Custom" }
                ]
                caption: page.quietRange
                    ? SettingsHelpers.formatMinutes(page.quietRange.start) + " – "
                        + SettingsHelpers.formatMinutes(page.quietRange.end) : ""
            }

            Revealer {
                id: quietReveal
                width: parent.width
                reveal: Settings.notifQuiet === "custom"
                Column {
                    width: quietReveal.width
                    spacing: 4
                    SliderRow {
                        width: parent.width
                        label: "Quiet from"
                        settingKey: "notifQuietStart"
                        resetLabel: "Quiet hours start"
                        min: 0; max: 1425; step: 15
                        valueLabel: SettingsHelpers.formatMinutes(Settings.notifQuietStart)
                    }
                    SliderRow {
                        width: parent.width
                        label: "Quiet until"
                        settingKey: "notifQuietEnd"
                        resetLabel: "Quiet hours end"
                        min: 0; max: 1425; step: 15
                        valueLabel: SettingsHelpers.formatMinutes(Settings.notifQuietEnd)
                    }
                }
            }

            SliderRow {
                width: parent.width
                label: "Duration"
                settingKey: "notifDuration"
                resetLabel: "Toast duration"
                min: 4; max: 20; step: 1; unit: "s"
            }
            Text {
                width: parent.width
                leftPadding: page.footnotePad
                text: "Critical alerts ignore the timer and stay until dismissed"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: Theme.textDim
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            PickerRow {
                width: parent.width
                label: "Position"
                settingKey: "notifPosition"
                resetLabel: "Toast position"
                model: [
                    { value: "top-left", label: "Top left" },
                    { value: "top-right", label: "Top right" },
                    { value: "bottom-left", label: "Bottom left" },
                    { value: "bottom-right", label: "Bottom right" }
                ]
            }
        }

        SettingsGroup {
            width: parent.width
            title: "Style"
            dirty: Settings.notifDensity !== Settings.defaults.notifDensity
                || Settings.notifIcons !== Settings.defaults.notifIcons
                || Settings.notifProgress !== Settings.defaults.notifProgress
                || Settings.notifBodyLines !== Settings.defaults.notifBodyLines
            onResetRequested: Settings.resetKeys(["notifDensity", "notifIcons",
                "notifProgress", "notifBodyLines"], "Notification style")

            PickerRow {
                width: parent.width
                label: "Density"
                settingKey: "notifDensity"
                resetLabel: "Toast density"
                model: [
                    { value: "compact", label: "Compact" },
                    { value: "default", label: "Default" },
                    { value: "roomy", label: "Roomy" }
                ]
            }
            SwitchRow {
                width: parent.width
                label: "App icons"
                settingKey: "notifIcons"
                description: "Show the sender's icon on each card"
            }
            SwitchRow {
                width: parent.width
                label: "Timeout progress"
                settingKey: "notifProgress"
                description: "Thin bar counting down a toast's remaining time"
            }
            SliderRow {
                width: parent.width
                label: "Body preview"
                settingKey: "notifBodyLines"
                min: 0; max: 3; step: 1
                valueLabel: Settings.notifBodyLines === 0 ? "hidden"
                    : Settings.notifBodyLines === 1 ? "1 line"
                    : Settings.notifBodyLines + " lines"
                valueWidth: 52
            }

            ResponsiveActionRow {
                width: parent.width
                actionsFirst: true
                description: Notifs.toastsSuppressed
                    ? "Toasts are silenced now; the sample will land in the center"
                    : "Fires a sample toast with these settings"
                SettingsAction {
                    text: "Send test notification"
                    glyph: "notifications"
                    onTriggered: page.sendTest()
                }
            }
        }
    }

    NumberAnimation {
        id: previewAnim
        target: page
        property: "previewProgress"
        from: 1; to: 0
        duration: Settings.notifDuration * 1000
        loops: Animation.Infinite
        running: Settings.notifProgress && page.visible
    }

    Connections {
        target: Settings
        function onNotifDurationChanged() {
            previewAnim.restart();
        }
    }
}
