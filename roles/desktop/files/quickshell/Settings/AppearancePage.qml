import QtQuick
import Quickshell
import Quickshell.Widgets
import QtQuick.Controls as Controls
import "../Common"
import "../Common/SettingsHelpers.js" as SettingsHelpers

// Appearance page (design v2): live bar miniature, height/radius sliders
// with presets, menu font picker, accent swatches + from-wallpaper accent.
SettingsPage {
    id: page

    readonly property var accentChoices: ["#9ecbeb", "#a992e0", "#79b88b", "#d3b47e", "#e8837a"]
    readonly property string tempPreview: Settings.unit === "f" ? "70°" : "21°"
    readonly property int accentHue: SettingsHelpers.hexHue(Settings.accent, 204)

    function pickAccent(value) {
        Settings.set("accent", value);
        Settings.set("accentWall", false);
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 10

        PreviewStrip {
            width: parent.width
            height: 80
            badgeText: "height " + Settings.barHeight + " · radius " + Settings.barRadius

            // The miniature is a real bar drawn at true metrics inside a
            // 0.72-scaled space — the design's 8.5px preview text without a
            // raw pixel size (it is fontCaption under the transform).
            Item {
                width: parent.width / 0.72
                height: parent.height / 0.72
                scale: 0.72
                transformOrigin: Item.TopLeft

                Rectangle {
                    x: 14
                    y: Settings.position === "top" ? 11 : parent.height - height - 11
                    width: parent.width - 28
                    height: Settings.barHeight
                    radius: Theme.clusterRadius
                    color: Theme.barBg

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Rectangle { width: 12; height: 5; radius: 2.5; color: Theme.accent }
                        Rectangle { width: 5; height: 5; radius: 2.5; color: Theme.dotDim }
                        Rectangle { width: 5; height: 5; radius: 2.5; color: Theme.dotDim }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: Qt.formatDateTime(clock.date, Settings.clock24 ? "HH:mm" : "h:mm AP")
                            + "  " + Qt.formatDateTime(clock.date, "ddd dd")
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontCaption
                        font.weight: Theme.weightSemibold
                        color: Theme.textHi
                        renderType: Text.QtRendering
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Repeater {
                            model: 3
                            delegate: Rectangle { width: 5; height: 5; radius: 2.5; color: Theme.dotDim }
                        }
                    }
                }
            }
        }

        SectionHeader {
            label: "BAR"
        }

        SliderRow {
            width: parent.width
            label: "Height"
            min: 24
            max: 44
            step: 1
            value: Settings.barHeight
            unit: "px"
            dirty: Settings.barHeight !== Settings.defaults.barHeight
            onMoved: value => Settings.set("barHeight", value)
            onResetRequested: Settings.resetKeys(["barHeight"])
        }

        SliderRow {
            width: parent.width
            label: "Corner radius"
            min: 0
            max: 16
            step: 1
            value: Settings.barRadius
            unit: "px"
            dimmed: !Settings.floating
            dirty: Settings.barRadius !== Settings.defaults.barRadius
            onMoved: value => Settings.set("barRadius", value)
            onResetRequested: Settings.resetKeys(["barRadius"])
        }

        PillRow {
            width: parent.width
            pillHeight: 22
            padH: 9
            model: [
                { value: 26, label: "Compact 26" },
                { value: 30, label: "Default 30" },
                { value: 36, label: "Roomy 36" }
            ]
            current: Settings.barHeight
            onPicked: value => Settings.set("barHeight", value)
        }

        SectionHeader {
            label: "MENU FONT"
            dirty: Settings.font !== Settings.defaults.font
            onResetRequested: Settings.resetKeys(["font"])
        }

        Column {
            width: parent.width
            spacing: 2

            Repeater {
                id: fontRepeater
                model: Settings.fontChoices

                delegate: Rectangle {
                    id: fontRow

                    required property var modelData
                    required property int index
                    readonly property bool selected: Settings.font === modelData.id

                    width: parent.width
                    height: 28
                    radius: 7
                    color: fontRow.selected ? Theme.accentAlpha(0.14)
                        : fontMouse.pressed ? Theme.hoverFillStrong
                        : fontMouse.containsMouse || activeFocus ? Theme.hoverFill : "transparent"
                    border.width: activeFocus ? 1 : 0
                    border.color: Theme.accent
                    activeFocusOnTab: fontRow.selected
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: fontRow.modelData.label + " menu font"
                    Accessible.checked: fontRow.selected
                    Accessible.onPressAction: Settings.set("font", fontRow.modelData.id)

                    Keys.onPressed: event => {
                        let next = -1;
                        if (event.key === Qt.Key_Up || event.key === Qt.Key_Left)
                            next = Math.max(0, index - 1);
                        else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right)
                            next = Math.min(Settings.fontChoices.length - 1, index + 1);
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                || event.key === Qt.Key_Space) {
                            Settings.set("font", modelData.id); event.accepted = true; return;
                        }
                        if (next >= 0) {
                            Settings.set("font", Settings.fontChoices[next].id);
                            fontRepeater.itemAt(next).forceActiveFocus();
                            event.accepted = true;
                        }
                    }

                    Rectangle {
                        id: radioRing
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 14
                        radius: 7
                        color: "transparent"
                        border.width: 1.5
                        border.color: fontRow.selected ? Theme.accent : Qt.rgba(1, 1, 1, 0.22)

                        Rectangle {
                            anchors.centerIn: parent
                            width: 6
                            height: 6
                            radius: 3
                            color: Theme.accent
                            visible: fontRow.selected
                        }
                    }

                    Text {
                        anchors.left: radioRing.right
                        anchors.leftMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        text: fontRow.modelData.label
                        font.family: fontRow.modelData.family
                        font.pixelSize: Theme.fontCaption
                        font.weight: Theme.weightMedium
                        color: fontRow.selected ? Theme.textHi : Theme.textMid
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDateTime(clock.date, Settings.clock24 ? "HH:mm" : "h:mm AP")
                            + " · Wed 06 · " + page.tempPreview
                        font.family: fontRow.modelData.family
                        font.pixelSize: Theme.fontCaption
                        color: Theme.textLow
                    }

                    MouseArea {
                        id: fontMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            fontRow.forceActiveFocus();
                            Settings.set("font", fontRow.modelData.id);
                        }
                    }
                }
            }
        }

        SectionHeader {
            label: "ACCENT"
            dirty: Settings.accent !== Settings.defaults.accent
                || Settings.accentWall !== Settings.defaults.accentWall
            onResetRequested: Settings.resetKeys(["accent", "accentWall"])
        }

        SliderRow {
            width: parent.width
            label: "Accent hue"
            min: 0
            max: 359
            step: 1
            value: page.accentHue
            unit: "°"
            hueTrack: true
            dirty: Settings.accent !== Settings.defaults.accent || Settings.accentWall
            onMoved: value => page.pickAccent(SettingsHelpers.hueToHex(value))
            onResetRequested: Settings.resetKeys(["accent", "accentWall"], "Accent")
        }

        Row {
            spacing: 9

            Repeater {
                id: swatchRepeater
                model: page.accentChoices

                delegate: Item {
                    id: swatch

                    required property string modelData
                    required property int index
                    readonly property bool selected: !Settings.accentWall
                        && Settings.accent === modelData

                    width: 26
                    height: 26
                    activeFocusOnTab: swatch.selected || (index === 0
                        && (Settings.accentWall
                            || page.accentChoices.indexOf(Settings.accent) === -1))
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: "Accent preset " + swatch.modelData
                    Accessible.checked: swatch.selected
                    Accessible.onPressAction: page.pickAccent(swatch.modelData)
                    Controls.ToolTip.visible: swatchMouse.containsMouse
                    Controls.ToolTip.text: "Use accent " + swatch.modelData

                    Keys.onPressed: event => {
                        let next = -1;
                        if (event.key === Qt.Key_Left || event.key === Qt.Key_Up)
                            next = Math.max(0, index - 1);
                        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down)
                            next = Math.min(page.accentChoices.length - 1, index + 1);
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                || event.key === Qt.Key_Space) {
                            page.pickAccent(modelData); event.accepted = true; return;
                        }
                        if (next >= 0) {
                            page.pickAccent(page.accentChoices[next]);
                            swatchRepeater.itemAt(next).forceActiveFocus();
                            event.accepted = true;
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        radius: 9
                        color: swatch.modelData
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 13
                        color: "transparent"
                        border.width: 1.5
                        border.color: swatch.modelData
                        visible: swatch.selected || swatch.activeFocus
                    }

                    MouseArea {
                        id: swatchMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            swatch.forceActiveFocus();
                            page.pickAccent(swatch.modelData);
                        }
                    }
                }
            }

            Rectangle {
                id: wallpaperAccentDivider
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 16
                color: Qt.rgba(1, 1, 1, 0.1)
            }

            Rectangle {
                id: wallpaperAccentButton
                anchors.verticalCenter: parent.verticalCenter
                width: fwRow.implicitWidth + 16
                height: 24
                radius: 12
                color: Settings.accentWall ? Theme.accentAlpha(0.16) : Theme.hoverFill
                activeFocusOnTab: true
                border.width: activeFocus ? 1 : 0
                border.color: Wallpaper.accentError !== "" ? Theme.red : Theme.accent
                Accessible.role: Accessible.CheckBox
                Accessible.name: "Derive accent from wallpaper"
                Accessible.checked: Settings.accentWall
                Accessible.onToggleAction: Settings.set("accentWall", !Settings.accentWall)

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                            || event.key === Qt.Key_Space) {
                        Settings.set("accentWall", !Settings.accentWall);
                        event.accepted = true;
                    }
                }

                Row {
                    id: fwRow
                    anchors.centerIn: parent
                    spacing: 6

                    ClippingRectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 14
                        radius: 7
                        color: Theme.barBg

                        Image {
                            anchors.fill: parent
                            source: Wallpaper.current !== "" ? Wallpaper.url(Wallpaper.current) : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 28
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Wallpaper.accentBusy ? "Extracting color…"
                            : Wallpaper.accentError !== "" ? Wallpaper.accentError
                            : "From wallpaper"
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontCaption
                        color: Settings.accentWall ? Theme.textHi : Theme.textMid
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        wallpaperAccentButton.forceActiveFocus();
                        Settings.set("accentWall", !Settings.accentWall);
                    }
                }
            }
        }
    }
}
