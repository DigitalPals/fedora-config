import QtQuick
import "../../Common"

// Output volume, inside the status pill. The wheel adjusts it; the pill's own
// click opens the Control Center, where the slider lives.
BarModule {
    id: root

    moduleId: "vol"
    spacing: 4
    detailSaving: Settings.modOpts.vol.showPct ? percentLabel.implicitWidth + spacing : 0

    Sym {
        anchors.verticalCenter: parent.verticalCenter
        name: Audio.muted || Audio.volume === 0 ? "volume_off"
            : Audio.volume < 50 ? "volume_down" : "volume_up"
        size: Theme.barIconSize
        fill: 1
        color: Audio.muted ? Theme.redText : Theme.textHi
    }

    Text {
        id: percentLabel
        visible: Settings.modOpts.vol.showPct && !root.compact
        anchors.verticalCenter: parent.verticalCenter
        text: Audio.volume + "%"
        font.family: Theme.fontMenu
        font.pixelSize: Theme.fontCaption
        font.weight: Theme.weightBold
        font.features: Theme.tabularNumberFeatures
        color: Audio.muted ? Theme.redText : Theme.textMid
    }

    // A handler rather than a MouseArea: it takes the wheel without also
    // taking the click that belongs to the pill this sits inside.
    WheelHandler {
        target: null
        onWheel: event => {
            const delta = event.angleDelta.y !== 0
                ? event.angleDelta.y : event.pixelDelta.y * 8;
            if (delta === 0)
                return;
            const steps = delta > 0 ? 1 : -1;
            Audio.stepVolume(steps * (Settings.modOpts.vol.step / 100));
        }
    }
}
