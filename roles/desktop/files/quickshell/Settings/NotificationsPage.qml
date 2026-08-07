import QtQuick
import Quickshell
import "../Common"
import "../Common/SettingsHelpers.js" as SettingsHelpers

// Notifications page (design 1c): live toast miniature over the wallpaper,
// BEHAVIOR (DND, quiet hours, duration, position) and STYLE (density, icons,
// timeout progress, body lines) sections, and a test-toast action.
SettingsPage {
    id: page

    readonly property var quietRange: SettingsHelpers.quietRange(Settings.notifQuiet,
        Settings.notifQuietStart, Settings.notifQuietEnd)
    readonly property int footnotePad: width < 440 ? 0
        : Settings.font === "mono" ? 132 : 100

    function sendTest() {
        Quickshell.execDetached(["notify-send", "-a", "Shell settings",
            "-i", "preferences-system-notifications", "Test notification",
            "Toasts use your current position, duration, and style settings."]);
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 8

        PreviewStrip {
            width: parent.width
            height: 104
            badgeText: Settings.notifPosition.replace("-", " ") + " · "
                + Settings.notifDuration + " s · " + Settings.notifDensity

            // Miniature drawn at true metrics inside a 0.72-scaled space,
            // the same convention as the Appearance bar preview.
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
                    color: Theme.barBg

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        Rectangle { width: 9; height: 4; radius: 2; color: Theme.accent }
                        Rectangle { width: 4; height: 4; radius: 2; color: Theme.dotDim }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        Repeater {
                            model: 3
                            delegate: Rectangle { width: 4; height: 4; radius: 2; color: Theme.dotDim }
                        }
                    }
                }

                Rectangle {
                    id: miniToast

                    readonly property bool onTop:
                        Settings.notifPosition.indexOf("top") === 0
                    readonly property bool onLeft:
                        Settings.notifPosition.indexOf("left") !== -1
                    readonly property int pad: Settings.notifDensity === "compact" ? 7
                        : Settings.notifDensity === "roomy" ? 14 : 10

                    width: 300
                    height: miniContent.implicitHeight + pad * 2
                        + (Settings.notifProgress ? 4 : 0)
                    x: onLeft ? 14 : parent.width - width - 14
                    y: onTop
                        ? (Settings.position === "top" ? miniBar.y + miniBar.height + 7 : 7)
                        : (Settings.position === "bottom" ? miniBar.y - height - 7
                            : parent.height - height - 7)
                    radius: 8
                    color: Theme.popBg
                    border.width: 1
                    border.color: Theme.popBorder

                    Row {
                        id: miniContent
                        x: miniToast.pad + 2
                        y: miniToast.pad
                        width: parent.width - (miniToast.pad + 2) * 2
                        spacing: 8

                        Image {
                            id: miniIcon
                            visible: Settings.notifIcons
                            width: 22
                            height: 22
                            source: "../assets/whatsapp.svg"
                            sourceSize: Qt.size(22, 22)
                            asynchronous: true
                        }

                        Column {
                            width: miniContent.width - (miniIcon.visible
                                ? miniIcon.width + miniContent.spacing : 0)
                            spacing: 2

                            Item {
                                width: parent.width
                                height: miniHeader.implicitHeight

                                Text {
                                    id: miniHeader
                                    anchors.left: parent.left
                                    width: parent.width - miniTime.width - 6
                                    text: "WhatsApp · Sarah Jansen"
                                    font.family: Theme.fontMenu
                                    font.pixelSize: Theme.fontCaption
                                    font.weight: Theme.weightSemibold
                                    color: Theme.textHi
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
                        anchors.leftMargin: 1
                        anchors.rightMargin: 1
                        anchors.bottomMargin: 1
                        height: 3
                        color: Qt.rgba(1, 1, 1, 0.07)

                        Rectangle {
                            height: parent.height
                            width: parent.width * page.previewProgress
                            color: Theme.accent
                        }
                    }
                }
            }
        }

        SectionHeader {
            label: "BEHAVIOR"
        }

        SwitchRow {
            width: parent.width
            label: "Do Not Disturb"
            description: "Silence toasts — everything still lands in the center"
            checked: Settings.notifDnd
            dirty: Settings.notifDnd !== Settings.defaults.notifDnd
            onToggled: value => Settings.set("notifDnd", value)
            onResetRequested: Settings.resetKeys(["notifDnd"], "Do Not Disturb")
        }

        PickerRow {
            width: parent.width
            label: "Quiet hours"
            model: [
                { value: "off", label: "Off" },
                { value: "nights", label: "Nights" },
                { value: "custom", label: "Custom" }
            ]
            current: Settings.notifQuiet
            caption: page.quietRange
                ? SettingsHelpers.formatMinutes(page.quietRange.start) + " – "
                    + SettingsHelpers.formatMinutes(page.quietRange.end)
                : ""
            dirty: Settings.notifQuiet !== Settings.defaults.notifQuiet
            onPicked: value => Settings.set("notifQuiet", value)
            onResetRequested: Settings.resetKeys(
                ["notifQuiet", "notifQuietStart", "notifQuietEnd"], "Quiet hours")
        }

        SliderRow {
            visible: Settings.notifQuiet === "custom"
            width: parent.width
            label: "Quiet from"
            min: 0
            max: 1425
            step: 15
            value: Settings.notifQuietStart
            valueLabel: SettingsHelpers.formatMinutes(Settings.notifQuietStart)
            dirty: Settings.notifQuietStart !== Settings.defaults.notifQuietStart
            onMoved: value => Settings.set("notifQuietStart", value)
            onResetRequested: Settings.resetKeys(["notifQuietStart"], "Quiet hours start")
        }

        SliderRow {
            visible: Settings.notifQuiet === "custom"
            width: parent.width
            label: "Quiet until"
            min: 0
            max: 1425
            step: 15
            value: Settings.notifQuietEnd
            valueLabel: SettingsHelpers.formatMinutes(Settings.notifQuietEnd)
            dirty: Settings.notifQuietEnd !== Settings.defaults.notifQuietEnd
            onMoved: value => Settings.set("notifQuietEnd", value)
            onResetRequested: Settings.resetKeys(["notifQuietEnd"], "Quiet hours end")
        }

        SliderRow {
            width: parent.width
            label: "Duration"
            min: 4
            max: 20
            step: 1
            value: Settings.notifDuration
            unit: "s"
            dirty: Settings.notifDuration !== Settings.defaults.notifDuration
            onMoved: value => Settings.set("notifDuration", value)
            onResetRequested: Settings.resetKeys(["notifDuration"], "Toast duration")
        }

        Text {
            width: parent.width
            leftPadding: page.footnotePad
            text: "Critical alerts ignore the timer and stay until dismissed"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            color: Theme.textDim
            wrapMode: Text.Wrap
        }

        PickerRow {
            width: parent.width
            label: "Position"
            model: [
                { value: "top-left", label: "Top left" },
                { value: "top-right", label: "Top right" },
                { value: "bottom-left", label: "Bottom left" },
                { value: "bottom-right", label: "Bottom right" }
            ]
            current: Settings.notifPosition
            dirty: Settings.notifPosition !== Settings.defaults.notifPosition
            onPicked: value => Settings.set("notifPosition", value)
            onResetRequested: Settings.resetKeys(["notifPosition"], "Toast position")
        }

        SectionHeader {
            label: "STYLE"
        }

        PickerRow {
            width: parent.width
            label: "Density"
            model: [
                { value: "compact", label: "Compact" },
                { value: "default", label: "Default" },
                { value: "roomy", label: "Roomy" }
            ]
            current: Settings.notifDensity
            dirty: Settings.notifDensity !== Settings.defaults.notifDensity
            onPicked: value => Settings.set("notifDensity", value)
            onResetRequested: Settings.resetKeys(["notifDensity"], "Toast density")
        }

        SwitchRow {
            width: parent.width
            label: "App icons"
            description: "Show the sender's icon on each card"
            checked: Settings.notifIcons
            dirty: Settings.notifIcons !== Settings.defaults.notifIcons
            onToggled: value => Settings.set("notifIcons", value)
            onResetRequested: Settings.resetKeys(["notifIcons"], "App icons")
        }

        SwitchRow {
            width: parent.width
            label: "Timeout progress"
            description: "Thin bar counting down a toast's remaining time"
            checked: Settings.notifProgress
            dirty: Settings.notifProgress !== Settings.defaults.notifProgress
            onToggled: value => Settings.set("notifProgress", value)
            onResetRequested: Settings.resetKeys(["notifProgress"], "Timeout progress")
        }

        SliderRow {
            width: parent.width
            label: "Body preview"
            min: 0
            max: 3
            step: 1
            value: Settings.notifBodyLines
            valueLabel: Settings.notifBodyLines === 0 ? "hidden"
                : Settings.notifBodyLines === 1 ? "1 line"
                : Settings.notifBodyLines + " lines"
            valueWidth: 52
            dirty: Settings.notifBodyLines !== Settings.defaults.notifBodyLines
            onMoved: value => Settings.set("notifBodyLines", value)
            onResetRequested: Settings.resetKeys(["notifBodyLines"], "Body preview")
        }

        Row {
            spacing: 10

            SettingsAction {
                text: "Send test notification"
                glyph: ""
                onTriggered: page.sendTest()
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Notifs.toastsSuppressed
                    ? "toasts are silenced right now — it will land in the center"
                    : "fires a sample toast with these settings"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.fontCaption
                color: Theme.textFaint
            }
        }
    }

    // Looping countdown for the preview card's progress bar; restarts when
    // the duration setting changes so the sweep always matches it.
    property real previewProgress: 1

    NumberAnimation {
        id: previewAnim
        target: page
        property: "previewProgress"
        from: 1
        to: 0
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
