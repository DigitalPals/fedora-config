import QtQuick
import ".."
import "../../Common"

// Now-playing chip; hidden unless a player reports a track.
    BarModule {
        id: mediaModule

    moduleId: "media"
        spacing: 2
        detailSaving: mediaTitle.implicitWidth > 0
            ? Math.min(mediaTitle.implicitWidth, Settings.modOpts.media.maxWidth) + 6 : 0

        Divider {
            visible: mediaModule.dividerBefore
        }

BarChip {
    id: mediaChip
    visible: Media.hasTrack
    host: mediaModule.host
    panelName: "media"
    isle: mediaModule.isle
    tooltip: Media.player ? Media.player.trackTitle : "Media"

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Media.glyph
        font.family: Theme.fontIcon
        font.pixelSize: Theme.barIconSize
        color: mediaChip.held || mediaChip.hovered ? Theme.textHi : Theme.icon

        Behavior on color {
            ColorAnimation { duration: Theme.chipFadeDuration }
        }
    }

    Text {
        id: mediaTitle
        visible: !mediaModule.compact
        anchors.verticalCenter: parent.verticalCenter
        text: {
            if (!Media.player)
                return "";
            const format = Settings.modOpts.media.titleFormat;
            const artist = Media.player.trackArtist;
            const title = Media.player.trackTitle;
            if (format === "title" || !artist)
                return title;
            return format === "artist-title"
                ? artist + " — " + title : title + " — " + artist;
        }
        font.family: Theme.fontMenu
        font.pixelSize: Theme.barTextSize
        color: mediaChip.held || mediaChip.hovered ? Theme.textHi : Theme.textMid
        elide: Text.ElideRight
        width: Math.min(implicitWidth, Settings.modOpts.media.maxWidth)

        Behavior on color {
            ColorAnimation { duration: Theme.chipFadeDuration }
        }
    }
}
    }
