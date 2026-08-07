import QtQuick
import ".."
import "../../Common"

// Output volume: glyph, optional percent, wheel to adjust.
BarModule {
    id: root

    moduleId: "vol"

    BarIcon {
        id: audioIcon

        host: root.host
        panelName: "audio"
        isle: root.isle
        glyph: Audio.muted || Audio.volume === 0 ? "" : Audio.volume < 50 ? "" : ""
        label: Settings.modOpts.vol.showPct ? Audio.volume + "%" : ""
        compact: root.compact
        alert: Audio.muted
        tooltip: "Audio " + Audio.volume + "%"
            + (Audio.muted ? " · muted" : "")
            + " · wheel volume"
            + (Settings.modOpts.vol.middleClick === "mute" ? " · middle mute" : "")
        tooltipAlign: 1
        onMiddleClicked: {
            if (Settings.modOpts.vol.middleClick === "mute")
                Audio.toggleMuted();
        }
        onWheeled: steps => Audio.stepVolume(steps * (Settings.modOpts.vol.step / 100))
    }
}
