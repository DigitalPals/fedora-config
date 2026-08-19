pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Controls as Controls
import "../Common"
import "../Common" as Common
import "../Common/SettingsHelpers.js" as SettingsHelpers

// Appearance owns theme, palette, fixed colors, and typography. Bar geometry
// lives on the Bar page so each page describes one coherent task.
SettingsPage {
    id: page

    readonly property var accentChoices: ["#9ecbeb", "#a992e0", "#79b88b", "#d3b47e", "#e8837a"]
    readonly property string tempPreview: Settings.unit === "f" ? "70°" : "21°"
    readonly property int accentHue: SettingsHelpers.hexHue(Settings.accent, 204)
    readonly property bool fixedPalette: Settings.paletteMode === "fixed"
    readonly property var paletteSwatches: [
        { label: "Surface", color: Theme.barBg },
        { label: "Panel", color: Theme.popBg },
        { label: "Group", color: Common.Palette.surfaceContainerHigh },
        { label: "Primary", color: Theme.accent },
        { label: "Outline", color: Theme.stroke },
        { label: "Error", color: Theme.red }
    ]
    readonly property int barColorIndex: {
        for (let i = 0; i < Settings.barColorChoices.length; ++i) {
            if (Settings.barColorChoices[i].id === Settings.barColorMode)
                return i;
        }
        return 0;
    }
    readonly property string barColorLabel: Settings.barColorChoices[barColorIndex].label

    function pickAccent(value) {
        Settings.set("accent", value);
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 12

        SettingsGroup {
            width: parent.width
            title: "Preview & preset"

            PreviewStrip {
                width: parent.width
                height: 88
                badgeText: Settings.paletteMode + " · "
                    + (Settings.glassEnabled ? "glass" : "solid") + " · "
                    + Settings.barStyle

                Item {
                    width: parent.width / 0.72
                    height: parent.height / 0.72
                    scale: 0.72
                    transformOrigin: Item.TopLeft

                    Rectangle {
                        readonly property real previewGap:
                            Settings.barStyle === "floating" ? 14 : 0
                        x: previewGap
                        y: Settings.position === "top" ? previewGap
                            : parent.height - height - previewGap
                        width: parent.width - previewGap * 2
                        height: Settings.barHeight
                        radius: Settings.barStyle === "floating" ? Settings.barRadius : 0
                        color: Theme.barSurface

                        HugCorner {
                            visible: Settings.barStyle === "hug"
                            x: 0
                            y: Settings.position === "top" ? parent.height : -height
                            bottomCorner: Settings.position === "bottom"
                        }
                        HugCorner {
                            visible: Settings.barStyle === "hug"
                            x: parent.width - width
                            y: Settings.position === "top" ? parent.height : -height
                            rightCorner: true
                            bottomCorner: Settings.position === "bottom"
                        }
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Rectangle { width: 12; height: 5; radius: 2.5; color: Theme.barAccent }
                            Rectangle { width: 5; height: 5; radius: 2.5; color: Theme.barDotDim }
                            Rectangle { width: 5; height: 5; radius: 2.5; color: Theme.barDotDim }
                        }
                        Text {
                            anchors.centerIn: parent
                            width: Math.max(0, parent.width - 140)
                            horizontalAlignment: Text.AlignHCenter
                            text: Qt.formatDateTime(clock.date, Settings.clock24 ? "HH:mm" : "h:mm AP")
                                + "  " + Qt.formatDateTime(clock.date, "ddd dd")
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontCaption
                            font.weight: Theme.weightSemibold
                            color: Theme.barTextHi
                            elide: Text.ElideRight
                            renderType: Text.QtRendering
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Repeater {
                                model: 3
                                delegate: Rectangle { width: 5; height: 5; radius: 2.5; color: Theme.barDotDim }
                            }
                        }
                    }
                }
            }

            ResponsiveActionRow {
                width: parent.width
                actionsFirst: true
                description: "Keeps module order and stored floating dimensions"
                SettingsAction {
                    text: "Apply Layered Hug"
                    glyph: "auto_awesome"
                    onTriggered: Settings.applyLayeredHugPreset()
                }
            }
        }

        SettingsGroup {
            width: parent.width
            title: "Theme"
            dirty: Settings.themeMode !== Settings.defaults.themeMode
                || Settings.glassEnabled !== Settings.defaults.glassEnabled
            onResetRequested: Settings.resetKeys(["themeMode", "glassEnabled"], "Theme")

            PickerRow {
                width: parent.width
                label: "Mode"
                settingKey: "themeMode"
                caption: "shell surfaces and text"
                captionMono: false
                model: [
                    { value: "dark", label: "Dark" },
                    { value: "light", label: "Light" }
                ]
            }
            SwitchRow {
                width: parent.width
                label: "Glass effect"
                settingKey: "glassEnabled"
                description: Settings.glassApplyError
                    ? "Surface changed, but the compositor blur rule could not be updated"
                    : "Blurred translucent shell surfaces; off uses opaque surfaces"
            }
        }

        SettingsGroup {
            width: parent.width
            title: "Colors"
            dirty: Settings.paletteMode !== Settings.defaults.paletteMode
                || Settings.barColorMode !== Settings.defaults.barColorMode
                || Settings.barCustomHue !== Settings.defaults.barCustomHue
                || Settings.barCustomSaturation !== Settings.defaults.barCustomSaturation
                || Settings.barCustomLightness !== Settings.defaults.barCustomLightness
                || Settings.accent !== Settings.defaults.accent
            onResetRequested: Settings.resetKeys(["paletteMode", "barColorMode",
                "barCustomHue", "barCustomSaturation", "barCustomLightness", "accent"], "Colors")

            PickerRow {
                width: parent.width
                label: "Colors"
                settingKey: "paletteMode"
                caption: Settings.paletteMode === "wallpaper"
                    ? "Material tonal spot" : "stored choices"
                captionMono: false
                model: [
                    { value: "wallpaper", label: "Wallpaper" },
                    { value: "fixed", label: "Fixed" }
                ]
            }

            Rectangle {
                width: parent.width
                height: paletteContent.implicitHeight + 18
                radius: Theme.rowRadius
                color: Theme.hoverFill
                Column {
                    id: paletteContent
                    x: 10
                    y: 9
                    width: parent.width - 20
                    spacing: 7
                    Row {
                        spacing: 9
                        Repeater {
                            model: page.paletteSwatches
                            delegate: Rectangle {
                                required property var modelData
                                width: 22; height: 22; radius: 11
                                color: modelData.color
                                border.width: 1
                                border.color: Theme.stroke
                                Accessible.role: Accessible.StaticText
                                Accessible.name: modelData.label + " palette color"
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        text: Settings.paletteMode !== "wallpaper"
                            ? "Fixed accent and menubar colors are active"
                            : Common.Palette.busy ? "Generating colors from the current wallpaper…"
                            : Common.Palette.ready ? "Wallpaper palette ready · light and dark cached"
                            : Common.Palette.error !== "" ? Common.Palette.error + " · using fixed colors"
                            : "Waiting for the wallpaper palette"
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontCaption
                        color: Settings.paletteMode === "wallpaper" && Common.Palette.error !== ""
                            ? Theme.redText : Theme.textDim
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
            }

            Revealer {
                id: fixedColorReveal
                width: parent.width
                reveal: page.fixedPalette

                Column {
                    width: fixedColorReveal.width
                    spacing: 6
                    SectionHeader { label: "BAR COLOR" }

                    Flow {
                        width: parent.width
                        spacing: 9
                        Repeater {
                            id: barColorRepeater
                            model: Settings.barColorChoices
                            delegate: Item {
                                id: colorChoice
                                required property var modelData
                                required property int index
                                readonly property bool selected: Settings.barColorMode === modelData.id
                                readonly property string previewHex: Settings.previewBarColor(modelData.id)
                                width: 34; height: 34
                                activeFocusOnTab: selected || (index === 0 && Settings.barColorMode === "")
                                Accessible.role: Accessible.RadioButton
                                Accessible.name: modelData.label + " menubar color"
                                Accessible.description: previewHex.toUpperCase()
                                Accessible.checked: selected
                                Accessible.onPressAction: Settings.set("barColorMode", modelData.id)
                                Controls.ToolTip.visible: colorMouse.containsMouse
                                Controls.ToolTip.text: modelData.label + " · " + previewHex.toUpperCase()
                                Keys.onPressed: event => {
                                    let next = -1;
                                    if (event.key === Qt.Key_Left || event.key === Qt.Key_Up)
                                        next = Math.max(0, index - 1);
                                    else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down)
                                        next = Math.min(Settings.barColorChoices.length - 1, index + 1);
                                    else if (event.key === Qt.Key_Home)
                                        next = 0;
                                    else if (event.key === Qt.Key_End)
                                        next = Settings.barColorChoices.length - 1;
                                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                            || event.key === Qt.Key_Space) {
                                        Settings.set("barColorMode", modelData.id);
                                        event.accepted = true; return;
                                    }
                                    if (next >= 0) {
                                        Settings.set("barColorMode", Settings.barColorChoices[next].id);
                                        barColorRepeater.itemAt(next).forceActiveFocus();
                                        event.accepted = true;
                                    }
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: colorChoice.selected ? 2 : colorChoice.activeFocus ? 1 : 0
                                    border.color: colorChoice.selected ? Theme.accent : Theme.textHi
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 22; height: 22; radius: 11
                                    color: colorChoice.previewHex
                                    border.width: 1
                                    border.color: Theme.stroke
                                }
                                MouseArea {
                                    id: colorMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        colorChoice.forceActiveFocus();
                                        Settings.set("barColorMode", colorChoice.modelData.id);
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 24
                        Text {
                            anchors.left: parent.left
                            anchors.right: colorValue.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.barColorLabel
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontCaption
                            font.weight: Theme.weightSemibold
                            color: Theme.textMid
                            elide: Text.ElideRight
                        }
                        Text {
                            id: colorValue
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, parent.width * 0.55)
                            horizontalAlignment: Text.AlignRight
                            text: (Settings.barColorMode === "default"
                                    || Settings.barColorMode === "macos" ? "adapts to theme · " : "")
                                + Settings.effectiveBarColor.toUpperCase()
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontCaption
                            color: Theme.textFaint
                            elide: Text.ElideLeft
                        }
                    }

                    Revealer {
                        id: customColorReveal
                        width: parent.width
                        reveal: Settings.barColorMode === "custom"
                        Column {
                            width: customColorReveal.width
                            spacing: 4
                            SliderRow {
                                width: parent.width
                                label: "Hue"
                                settingKey: "barCustomHue"
                                min: 0; max: 359; step: 1; unit: "°"
                                hueTrack: true
                            }
                            SliderRow {
                                width: parent.width
                                label: "Saturation"
                                settingKey: "barCustomSaturation"
                                min: 0; max: 100; step: 1; unit: "%"
                                colorTrack: true
                                trackStart: SettingsHelpers.hslToHex(Settings.barCustomHue, 0,
                                    Settings.barCustomLightness)
                                trackMiddle: SettingsHelpers.hslToHex(Settings.barCustomHue, 50,
                                    Settings.barCustomLightness)
                                trackEnd: SettingsHelpers.hslToHex(Settings.barCustomHue, 100,
                                    Settings.barCustomLightness)
                            }
                            SliderRow {
                                width: parent.width
                                label: "Lightness"
                                settingKey: "barCustomLightness"
                                min: 0; max: 100; step: 1; unit: "%"
                                colorTrack: true
                                trackStart: "#000000"
                                trackMiddle: SettingsHelpers.hslToHex(Settings.barCustomHue,
                                    Settings.barCustomSaturation, 50)
                                trackEnd: "#ffffff"
                            }
                        }
                    }

                    SectionHeader { label: "ACCENT" }
                    SliderRow {
                        width: parent.width
                        label: "Accent hue"
                        resetKeys: ["accent"]
                        resetLabel: "Accent"
                        min: 0; max: 359; step: 1; unit: "°"
                        value: page.accentHue
                        hueTrack: true
                        dirty: Settings.accent !== Settings.defaults.accent
                        onMoved: value => page.pickAccent(SettingsHelpers.hueToHex(value))
                    }
                    Flow {
                        width: parent.width
                        spacing: 9
                        Repeater {
                            id: swatchRepeater
                            model: page.accentChoices
                            delegate: Item {
                                id: swatch
                                required property string modelData
                                required property int index
                                readonly property bool selected: Settings.accent === modelData
                                width: 28; height: 28
                                activeFocusOnTab: selected || (index === 0
                                    && page.accentChoices.indexOf(Settings.accent) === -1)
                                Accessible.role: Accessible.RadioButton
                                Accessible.name: "Accent preset " + modelData
                                Accessible.checked: selected
                                Accessible.onPressAction: page.pickAccent(modelData)
                                Controls.ToolTip.visible: swatchMouse.containsMouse
                                Controls.ToolTip.text: "Use accent " + modelData
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
                                    width: 18; height: 18; radius: 9
                                    color: swatch.modelData
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 14
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
                    }
                }
            }
        }

        SettingsGroup {
            width: parent.width
            title: "Typography"
            dirty: Settings.font !== Settings.defaults.font
            onResetRequested: Settings.resetKeys(["font"], "Typography")

            Column {
                width: parent.width
                spacing: 3
                Repeater {
                    id: fontRepeater
                    model: Settings.fontChoices
                    delegate: Rectangle {
                        id: fontRow
                        required property var modelData
                        required property int index
                        readonly property bool selected: Settings.font === modelData.id
                        width: parent.width
                        height: 38
                        radius: Theme.rowRadius
                        color: selected ? Theme.accentAlpha(0.14) : "transparent"
                        border.width: activeFocus ? 1 : 0
                        border.color: Theme.accent
                        activeFocusOnTab: selected
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: modelData.label + " menu font"
                        Accessible.checked: selected
                        Accessible.onPressAction: {
                            fontState.pulseCenter();
                            Settings.set("font", modelData.id);
                        }
                        Keys.onPressed: event => {
                            let next = -1;
                            if (event.key === Qt.Key_Up || event.key === Qt.Key_Left)
                                next = Math.max(0, index - 1);
                            else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right)
                                next = Math.min(Settings.fontChoices.length - 1, index + 1);
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                    || event.key === Qt.Key_Space) {
                                fontState.pulseCenter();
                                Settings.set("font", modelData.id); event.accepted = true; return;
                            }
                            if (next >= 0) {
                                Settings.set("font", Settings.fontChoices[next].id);
                                fontRepeater.itemAt(next).forceActiveFocus();
                                event.accepted = true;
                            }
                        }
                        StateLayer {
                            id: fontState
                            anchors.fill: parent
                            radius: parent.radius
                            hovered: fontMouse.containsMouse
                            pressed: fontMouse.pressed
                            focused: fontRow.activeFocus
                            tint: fontRow.selected ? Theme.accent : Theme.textHi
                            pressPoint: Qt.point(fontMouse.mouseX, fontMouse.mouseY)
                        }
                        Rectangle {
                            id: radioRing
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14; height: 14; radius: 7
                            color: "transparent"
                            border.width: 1.5
                            border.color: fontRow.selected ? Theme.accent : Qt.rgba(1, 1, 1, 0.22)
                            Rectangle {
                                anchors.centerIn: parent
                                width: 6; height: 6; radius: 3
                                color: Theme.accent
                                visible: fontRow.selected
                            }
                        }
                        Text {
                            id: fontName
                            anchors.left: radioRing.right
                            anchors.leftMargin: 9
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, parent.width * 0.42 - x)
                            text: fontRow.modelData.label
                            font.family: fontRow.modelData.family
                            font.pixelSize: Theme.fontCaption
                            font.weight: Theme.weightMedium
                            color: fontRow.selected ? Theme.textHi : Theme.textMid
                            elide: Text.ElideRight
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: parent.width * 0.44
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            text: Qt.formatDateTime(clock.date, Settings.clock24 ? "HH:mm" : "h:mm AP")
                                + " · Wed 06 · " + page.tempPreview
                            font.family: fontRow.modelData.family
                            font.pixelSize: Theme.fontCaption
                            color: Theme.textLow
                            elide: Text.ElideLeft
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
        }
    }
}
