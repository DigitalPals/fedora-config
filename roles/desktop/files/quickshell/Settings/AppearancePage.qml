import QtQuick
import Quickshell
import Quickshell.Widgets
import "../Common"

// Appearance page (design v2): live bar miniature, height/radius sliders
// with presets, menu font picker, accent swatches + from-wallpaper accent.
Item {
    id: page

    readonly property var accentChoices: ["#9ecbeb", "#a992e0", "#79b88b", "#d3b47e", "#e8837a"]
    readonly property string tempPreview: Settings.unit === "f" ? "70°" : "21°"

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
            dirty: Settings.barRadius !== Settings.defaults.barRadius
            onMoved: value => Settings.set("barRadius", value)
            onResetRequested: Settings.resetKeys(["barRadius"])
        }

        PillRow {
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
                model: Settings.fontChoices

                delegate: Rectangle {
                    id: fontRow

                    required property var modelData
                    readonly property bool selected: Settings.font === modelData.id

                    width: parent.width
                    height: 28
                    radius: 7
                    color: fontRow.selected ? Theme.accentAlpha(0.09) : "transparent"

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
                        anchors.fill: parent
                        onClicked: Settings.set("font", fontRow.modelData.id)
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

        Row {
            spacing: 9

            Repeater {
                model: page.accentChoices

                delegate: Item {
                    id: swatch

                    required property string modelData
                    readonly property bool selected: !Settings.accentWall
                        && Settings.accent === modelData

                    width: 26
                    height: 26

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
                        visible: swatch.selected
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            Settings.set("accent", swatch.modelData);
                            Settings.set("accentWall", false);
                        }
                    }
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 16
                color: Qt.rgba(1, 1, 1, 0.1)
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: fwRow.implicitWidth + 16
                height: 24
                radius: 12
                color: Settings.accentWall ? Theme.accentAlpha(0.16) : Theme.hoverFill

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
                        text: "From wallpaper"
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontCaption
                        color: Settings.accentWall ? Theme.textHi : Theme.textMid
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Settings.set("accentWall", !Settings.accentWall)
                }
            }
        }
    }
}
