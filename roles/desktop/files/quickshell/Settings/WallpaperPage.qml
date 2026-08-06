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

    function focusThumbnail(index) {
        const clamped = Math.max(0, Math.min(Wallpaper.files.length - 1, index));
        const item = thumbRepeater.itemAt(clamped);
        if (!item)
            return;
        item.forceActiveFocus();
        const top = item.y;
        const bottom = top + item.height;
        if (top < grid.contentY)
            grid.contentY = top;
        else if (bottom > grid.contentY + grid.height)
            grid.contentY = bottom - grid.height;
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

        readonly property int cellWidth: Math.floor((width - 7) / 2)

        Grid {
            id: gridFlow
            columns: 2
            spacing: 7

            Repeater {
                id: thumbRepeater
                model: Wallpaper.files

                delegate: ClippingRectangle {
                    id: thumb

                    required property string modelData
                    required property int index
                    readonly property bool current:
                        page.basename(Wallpaper.current) === page.basename(modelData)

                    width: grid.cellWidth
                    height: Math.max(92, Math.min(132, width * 0.58))
                    radius: 8
                    color: Theme.cardFill
                    contentInsideBorder: true
                    activeFocusOnTab: true
                    border.width: thumb.current || activeFocus ? 2 : 0
                    border.color: activeFocus ? Theme.textHi : Theme.accent

                    Keys.onPressed: event => {
                        let next = -1;
                        if (event.key === Qt.Key_Left)
                            next = index - 1;
                        else if (event.key === Qt.Key_Right)
                            next = index + 1;
                        else if (event.key === Qt.Key_Up)
                            next = index - 2;
                        else if (event.key === Qt.Key_Down)
                            next = index + 2;
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                || event.key === Qt.Key_Space) {
                            Wallpaper.set(modelData); event.accepted = true; return;
                        }
                        if (next >= 0 && next < Wallpaper.files.length) {
                            page.focusThumbnail(next); event.accepted = true;
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: Theme.cardFill
                        visible: wallImage.status !== Image.Ready

                        Text {
                            anchors.centerIn: parent
                            text: wallImage.status === Image.Error ? "Could not load" : "Loading…"
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontCaption
                            color: Theme.textFaint
                        }
                    }

                    Image {
                        id: wallImage
                        anchors.fill: parent
                        source: Wallpaper.url(thumb.modelData)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 330
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: fileName.implicitHeight + 10
                        visible: thumbMouse.containsMouse || thumb.activeFocus
                        color: Qt.rgba(0, 0, 0, 0.62)

                        Text {
                            id: fileName
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 7
                            anchors.rightMargin: 7
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.basename(thumb.modelData)
                            elide: Text.ElideMiddle
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.fontCaption
                            color: Theme.textHi
                        }
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
                        id: thumbMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            thumb.forceActiveFocus();
                            Wallpaper.set(thumb.modelData);
                        }
                    }
                }
            }

            Rectangle {
                id: shuffleTile
                width: grid.cellWidth
                height: Math.max(92, Math.min(132, width * 0.58))
                radius: 8
                color: shuffleMouse.containsMouse ? Theme.cardFill : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.16)
                activeFocusOnTab: true

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                            || event.key === Qt.Key_Space) {
                        Wallpaper.shuffle(); event.accepted = true;
                    }
                }

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
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        shuffleTile.forceActiveFocus();
                        Wallpaper.shuffle();
                    }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: Wallpaper.loading || Wallpaper.files.length === 0
            text: Wallpaper.loading ? "Loading wallpapers…"
                : "No images found in " + page.dirLabel
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontSecondary
            color: Theme.textLow
        }

        Rectangle {
            anchors.right: parent.right
            y: grid.visibleArea.yPosition * (parent.height - height)
            width: 3
            height: Math.max(22, grid.visibleArea.heightRatio * parent.height)
            radius: 2
            visible: grid.contentHeight > grid.height + 1
            color: Theme.accentAlpha(grid.moving ? 0.8 : 0.35)
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
        width: parent.width
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
            id: openFolder
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Open folder"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.weightMedium
            color: Theme.accent
            activeFocusOnTab: true

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                        || event.key === Qt.Key_Space) {
                    Quickshell.execDetached(["xdg-open", Wallpaper.dir]);
                    event.accepted = true;
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["xdg-open", Wallpaper.dir])
            }
        }
    }
}
