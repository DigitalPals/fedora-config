import QtQuick
import Quickshell.Services.Mpris
import "../Common"
import "../Common/StatusHelpers.js" as StatusHelpers
import "../Common/Format.js" as Format

// Media view (design t5): header with source switcher, full-bleed
// artwork, centered track info, seek bar, transport row. Volume lives in
// the audio popout; this view is playback only.
Surface {
    id: root

    // This is the deliberate full-bleed exception: the artwork and its
    // gradient reach the panel edge while each text/control section keeps
    // its own twelve-pixel-or-larger inset.
    padding: 0

    readonly property var players: Media.players
    property int sourceIdx: -1

    // The source switcher's manual pick wins; without one this falls back to
    // Media.player, which is literally what the bar chip shows.
    readonly property var player: {
        if (sourceIdx >= 0 && sourceIdx < players.length)
            return players[sourceIdx];
        return Media.player;
    }

    property real pos: 0
    readonly property real len: player && player.lengthSupported ? player.length : 0
    readonly property bool hasArt: player !== null && player.trackArtUrl !== ""

    Timer {
        interval: 1000
        running: root.visible && root.player !== null
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pos = root.player && root.player.positionSupported ? root.player.position : 0
    }

    // ---- Header: title + source switcher -----------------------------
    Item {
        width: parent.width
        height: Theme.listRowHeight

        Text {
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            text: "Media"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontBody
            font.weight: Theme.weightSemibold
            color: Theme.textHi
        }

        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: srcRow.implicitWidth + 16
            height: Theme.controlHeight
            radius: Theme.chipRadius
            color: srcMouse.containsMouse && root.players.length > 1 ? Theme.hoverFill : "transparent"

            Row {
                id: srcRow
                anchors.centerIn: parent
                spacing: 7

                Sym {
                    anchors.verticalCenter: parent.verticalCenter
                    name: StatusHelpers.playerGlyph(root.player)
                    size: Theme.fontBody
                    color: srcMouse.containsMouse ? Theme.textHi : Theme.textLow
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.player ? root.player.identity : "No player"
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.fontBody
                    font.weight: Theme.weightSemibold
                    color: srcMouse.containsMouse ? Theme.textHi : Theme.textLow
                }

                Sym {
                    visible: root.players.length > 1
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron_right"
                    size: Theme.fontCaption
                    color: srcMouse.containsMouse ? Theme.textHi : Theme.textLow
                }
            }

            MouseArea {
                id: srcMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: root.players.length > 1
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const cur = root.players.indexOf(root.player);
                    root.sourceIdx = (cur + 1) % root.players.length;
                }
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(1, 1, 1, 0.07)
    }

    // ---- Full-bleed artwork ------------------------------------------
    Item {
        width: parent.width
        height: 190

        // Fallback wash when the player has no art.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: "#5a4a6b"
                }

                GradientStop {
                    position: 1
                    color: "#8a6a5b"
                }
            }
        }

        Sym {
            visible: !root.hasArt
            anchors.centerIn: parent
            name: "music_note"
            size: Theme.fontHero
            color: Qt.rgba(1, 1, 1, 0.35)
        }

        Image {
            visible: root.hasArt
            anchors.fill: parent
            source: root.player ? root.player.trackArtUrl : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(720, 380)
            asynchronous: true
        }

        // Inset shade where the artwork meets the panel body.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 26
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: "transparent"
                }

                GradientStop {
                    position: 1
                    color: Qt.rgba(0, 0, 0, 0.45)
                }
            }
        }
    }

    // ---- Track info (centered) ---------------------------------------
    Column {
        width: parent.width
        topPadding: 12
        spacing: 5

        Text {
            width: parent.width - 32
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            text: root.player && root.player.trackTitle !== "" ? root.player.trackTitle : "Nothing playing"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontBody
            font.weight: Theme.weightSemibold
            color: Theme.textHi
            elide: Text.ElideRight
        }

        Text {
            width: parent.width - 32
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            visible: text !== ""
            text: root.player ? root.player.trackArtist : ""
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontBody
            font.weight: Theme.weightSemibold
            color: Theme.textMid
            elide: Text.ElideRight
        }

        Text {
            width: parent.width - 32
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            visible: text !== ""
            text: root.player ? root.player.trackAlbum : ""
            font.family: Theme.fontMenu
            font.pixelSize: Theme.fontSecondary
            font.weight: Theme.weightMedium
            color: Theme.textDim
            elide: Text.ElideRight
        }
    }

    // ---- Seek ---------------------------------------------------------
    Column {
        width: parent.width - 36
        anchors.horizontalCenter: parent.horizontalCenter
        topPadding: 8

        HSlider {
            width: parent.width
            value: root.len > 0 ? root.pos / root.len : 0
            dimmed: !root.player || !root.player.canSeek || root.len <= 0
            accessibleName: "Seek"
            onMoved: v => {
                if (root.player && root.player.canSeek && root.len > 0) {
                    root.player.position = v * root.len;
                    root.pos = v * root.len;
                }
            }
        }

        Item {
            width: parent.width
            height: Math.max(positionText.implicitHeight, durationText.implicitHeight)

            Text {
                id: positionText
                anchors.verticalCenter: parent.verticalCenter
                text: Format.mmss(root.pos)
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSecondary
                font.weight: Theme.weightMedium
                color: Theme.textDim
            }

            Text {
                id: durationText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.len > 0 ? Format.mmss(root.len) : "--:--"
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSecondary
                font.weight: Theme.weightMedium
                color: Theme.textDim
            }
        }
    }

    // ---- Transport -----------------------------------------------------
    Item {
        width: parent.width
        height: 62

        Row {
            anchors.centerIn: parent
            spacing: 8

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.controlHeight
                height: Theme.controlHeight
                radius: 15
                color: shuffleMouse.containsMouse ? Theme.hoverFill : "transparent"
                opacity: root.player && root.player.shuffleSupported ? 1 : 0.4

                Sym {
                    anchors.centerIn: parent
                    name: "shuffle"
                    size: Theme.fontSecondary
                    color: root.player && root.player.shuffle ? Theme.accent : shuffleMouse.containsMouse ? Theme.textHi : Theme.textDim
                }

                MouseArea {
                    id: shuffleMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.player !== null && root.player.shuffleSupported
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.player.shuffle = !root.player.shuffle
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 36
                radius: 18
                color: prevMouse.containsMouse ? Theme.hoverFill : "transparent"
                opacity: root.player && root.player.canGoPrevious ? 1 : 0.4

                Sym {
                    anchors.centerIn: parent
                    name: "skip_previous"
                    size: Theme.fontBody
                    color: prevMouse.containsMouse ? Theme.textHi : Theme.textMid
                }

                MouseArea {
                    id: prevMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.player !== null && root.player.canGoPrevious
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.player.previous()
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                height: 44
                radius: 22
                color: playMouse.containsMouse ? Theme.accentHover : Theme.accent

                Sym {
                    anchors.centerIn: parent
                    name: root.player && root.player.isPlaying ? "pause" : "play_arrow"
                    size: Theme.fontHeading
                    color: Theme.accentFg
                }

                MouseArea {
                    id: playMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.player !== null
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.player.togglePlaying()
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 36
                radius: 18
                color: nextMouse.containsMouse ? Theme.hoverFill : "transparent"
                opacity: root.player && root.player.canGoNext ? 1 : 0.4

                Sym {
                    anchors.centerIn: parent
                    name: "skip_next"
                    size: Theme.fontBody
                    color: nextMouse.containsMouse ? Theme.textHi : Theme.textMid
                }

                MouseArea {
                    id: nextMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.player !== null && root.player.canGoNext
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.player.next()
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.controlHeight
                height: Theme.controlHeight
                radius: 15
                color: loopMouse.containsMouse ? Theme.hoverFill : "transparent"
                opacity: root.player && root.player.loopSupported ? 1 : 0.4

                Sym {
                    anchors.centerIn: parent
                    name: root.player && root.player.loopState === MprisLoopState.Track ? "repeat" : "repeat"
                    size: Theme.fontSecondary
                    color: root.player && root.player.loopState !== MprisLoopState.None ? Theme.accent : loopMouse.containsMouse ? Theme.textHi : Theme.textDim
                }

                MouseArea {
                    id: loopMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.player !== null && root.player.loopSupported
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const s = root.player.loopState;
                        root.player.loopState = s === MprisLoopState.None ? MprisLoopState.Playlist : s === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None;
                    }
                }
            }
        }
    }
}
