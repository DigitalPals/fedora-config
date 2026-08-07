import QtQuick
import Quickshell
import Quickshell.Widgets
import "../Common"

// Wallpaper thumbnails are virtualized so very large folders do not create
// an Image and texture for every file at once.
Item {
    id: page

    function basename(path) {
        return Wallpaper.basename(path);
    }

    function focusThumbnail(index) {
        const clamped = Math.max(0, Math.min(wallGrid.count - 1, index));
        wallGrid.currentIndex = clamped;
        wallGrid.positionViewAtIndex(clamped, GridView.Contain);
        Qt.callLater(() => {
            if (wallGrid.currentItem)
                wallGrid.currentItem.forceActiveFocus();
        });
    }

    readonly property string dirLabel: Settings.wallDir

    SectionHeader {
        id: wallHeader
        label: "WALLPAPER"
        dirty: Settings.wall !== Settings.defaults.wall
            || Settings.wallDir !== Settings.defaults.wallDir
        onResetRequested: Settings.resetKeys(["wall", "wallDir"], "Wallpaper")
    }

    GridView {
        id: wallGrid
        anchors.top: wallHeader.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: rotateHeader.top
        anchors.bottomMargin: 10
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cellWidth: Math.floor(width / 2)
        cellHeight: Math.max(99, Math.min(139, cellWidth * 0.58 + 7))
        model: Wallpaper.files.length + 1
        currentIndex: 0

        delegate: Item {
            id: cell
            required property int index
            readonly property bool shuffle: index === Wallpaper.files.length
            readonly property string imagePath: shuffle ? "" : Wallpaper.files[index]
            readonly property string thumbnailSource: shuffle ? ""
                : Wallpaper.thumbnailFor(imagePath)
            readonly property bool current: !shuffle
                && page.basename(Wallpaper.current) === page.basename(imagePath)

            width: wallGrid.cellWidth
            height: wallGrid.cellHeight
            activeFocusOnTab: index === wallGrid.currentIndex
            Accessible.role: Accessible.Button
            Accessible.name: shuffle ? "Shuffle wallpaper now"
                : "Use wallpaper " + page.basename(imagePath)
            Accessible.selected: current
            Accessible.onPressAction: cell.activate()

            Component.onCompleted: {
                if (!shuffle)
                    Wallpaper.requestThumbnail(imagePath);
            }

            onImagePathChanged: {
                if (!shuffle)
                    Wallpaper.requestThumbnail(imagePath);
            }

            function activate() {
                wallGrid.currentIndex = index;
                if (shuffle)
                    Wallpaper.shuffle();
                else
                    Wallpaper.set(imagePath);
            }

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
                    activate();
                    event.accepted = true;
                    return;
                }
                if (next >= 0 && next < wallGrid.count) {
                    page.focusThumbnail(next);
                    event.accepted = true;
                }
            }

            ClippingRectangle {
                anchors.fill: parent
                anchors.rightMargin: 7
                anchors.bottomMargin: 7
                radius: 8
                color: Theme.cardFill
                contentInsideBorder: true
                border.width: cell.current || cell.activeFocus ? 2 : cell.shuffle ? 1 : 0
                border.color: cell.activeFocus ? Theme.textHi
                    : cell.current ? Theme.accent : Qt.rgba(1, 1, 1, 0.16)

                Rectangle {
                    anchors.fill: parent
                    color: Theme.cardFill
                    visible: !cell.shuffle && wallImage.status !== Image.Ready

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
                    visible: !cell.shuffle
                    source: cell.thumbnailSource
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 330
                }

                Column {
                    visible: cell.shuffle
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ""
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

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: fileName.implicitHeight + 10
                    visible: !cell.shuffle && (cellMouse.containsMouse || cell.activeFocus)
                    color: Qt.rgba(0, 0, 0, 0.62)

                    Text {
                        id: fileName
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 7
                        anchors.rightMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.basename(cell.imagePath)
                        elide: Text.ElideMiddle
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.fontCaption
                        color: Theme.textHi
                    }
                }

                Rectangle {
                    visible: cell.current
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
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        cell.forceActiveFocus();
                        cell.activate();
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
    }

    SectionHeader {
        id: rotateHeader
        anchors.bottom: rotatePills.top
        anchors.bottomMargin: 10
        label: "ROTATE WALLPAPER"
        dirty: Settings.shuffle !== Settings.defaults.shuffle
        onResetRequested: Settings.resetKeys(["shuffle"], "Wallpaper rotation")
    }

    PillRow {
        id: rotatePills
        anchors.bottom: folderError.visible ? folderError.top : folderRow.top
        anchors.bottomMargin: 10
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

    Text {
        id: folderError
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: folderRow.top
        anchors.bottomMargin: 5
        visible: Wallpaper.directoryError !== ""
        text: Wallpaper.directoryError
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        color: Theme.redText
        Accessible.role: Accessible.AlertMessage
        Accessible.name: text
    }

    Item {
        id: folderRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 24

        Text {
            anchors.left: parent.left
            anchors.right: folderActions.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: page.dirLabel + " · " + Wallpaper.files.length + " images"
            elide: Text.ElideMiddle
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontCaption
            color: Theme.textFaint
        }

        Row {
            id: folderActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            SettingsAction {
                height: 24
                text: "Choose folder"
                glyph: ""
                Accessible.name: "Choose wallpaper folder"
                onTriggered: folderDialog.openAt(Settings.wallDir)
            }
            SettingsAction {
                height: 24
                text: "Open"
                glyph: ""
                Accessible.name: "Open wallpaper folder"
                onTriggered: Quickshell.execDetached(["xdg-open", Wallpaper.dir])
            }
        }
    }

    FolderDialog {
        id: folderDialog
        onFolderChosen: path => Wallpaper.requestDirectory(path)
    }
}
