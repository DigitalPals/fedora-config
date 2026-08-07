pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "StatusHelpers.js" as StatusHelpers

// Which MPRIS player the shell is talking about. The selection rule
// (playing → paused → first) lives in StatusHelpers; this is the reactive
// wrapper the bar chip and the media popover both read, so a manual pick in
// the popover's source switcher starts from the same default the bar shows.
Singleton {
    id: root

    readonly property var players: Mpris.players.values
    readonly property var player: StatusHelpers.activePlayer(players)

    // A player with no track is a running app, not something to show — the
    // bar module's auto-rule turns on exactly here.
    readonly property bool hasTrack: player !== null && player.trackTitle !== ""

    readonly property string glyph: StatusHelpers.playerGlyph(player)
}
