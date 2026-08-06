import QtQuick
import Quickshell
import Quickshell.Widgets
import "../Common"

// Wallpaper page (design v2): thumbnail grid with the current selection
// ringed, shuffle-now tile, rotate interval, and the folder footer.
Item {
    id: page

    function basename(path) {
        return path.split("/").pop();
    }

    readonly property string dirLabel:
        Wallpaper.dir.replace(Quickshell.env("HOME"), "~")

    SectionHeader {
        id: wallHeader
        label: "WALLPAPER"
        dirty: Settings.wall !== Settings.defaults.wall
        onResetRequested: Settings.resetKeys(["wall"])
    }

    Flickable {
        id: grid
        anchors.top: wallHeader.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: rotateHeader.top
        anchors.bottomMargin: 10
        contentHeight: gridFlow.height
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        clip: true

        readonly property int cellWidth: Math.floor((width - 14) / 3)

        Grid {
            id: gridFlow
            columns: 3
            spacing: 7

            Repeater {
                model: Wallpaper.files

                delegate: ClippingRectangle {
                    id: thumb

                    required property string modelData
                    readonly property bool current:
                        page.basename(Wallpaper.current) === page.basename(modelData)

                    width: grid.cellWidth
                    height: 92
                    radius: 8
                    color: Theme.cardFill
                    border.width: thumb.current ? 2 : 0
                    border.color: Theme.accent
                    contentInsideBorder: true

                    Image {
                        anchors.fill: parent
                        source: Wallpaper.url(thumb.modelData)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 330
                    }

                    Rectangle {
                        visible: thumb.current
                        anchors.top: parent.top
                        anchors.topMargin: 6
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        width: 16
                        height: 16
                        radius: 8
                        color: Theme.accent

                        Text {
                            anchors.centerIn: parent
                            text: "✓"
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontCaption
                            font.weight: Theme.weightBold
                            color: Theme.accentFg
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: Wallpaper.set(thumb.modelData)
                    }
                }
            }

            Rectangle {
                width: grid.cellWidth
                height: 92
                radius: 8
                color: shuffleMouse.containsMouse ? Theme.cardFill : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.16)

                Column {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "" // shuffle
                        font.family: Theme.fontIcon
                        font.pixelSize: Theme.fontSecondary
                        color: Theme.textLow
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Shuffle now"
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontCaption
                        font.weight: Theme.weightMedium
                        color: Theme.textLow
                    }
                }

                MouseArea {
                    id: shuffleMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Wallpaper.shuffle()
                }
            }
        }
    }

    SectionHeader {
        id: rotateHeader
        anchors.bottom: rotatePills.top
        anchors.bottomMargin: 10
        label: "ROTATE WALLPAPER"
        dirty: Settings.shuffle !== Settings.defaults.shuffle
        onResetRequested: Settings.resetKeys(["shuffle"])
    }

    PillRow {
        id: rotatePills
        anchors.bottom: folderRow.top
        anchors.bottomMargin: 12
        model: [
            { value: "Off", label: "Off" },
            { value: "15m", label: "15 min" },
            { value: "1h", label: "1 hour" },
            { value: "1d", label: "Daily" }
        ]
        current: Settings.shuffle
        onPicked: value => Settings.set("shuffle", value)
    }

    Item {
        id: folderRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 16

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: page.dirLabel + " · " + Wallpaper.files.length + " images"
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontCaption
            color: Theme.textFaint
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Open folder"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.weightMedium
            color: Theme.accent

            MouseArea {
                anchors.fill: parent
                onClicked: Quickshell.execDetached(["xdg-open", Wallpaper.dir])
            }
        }
    }
}
