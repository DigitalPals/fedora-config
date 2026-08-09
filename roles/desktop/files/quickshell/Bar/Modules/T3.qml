import QtQuick
import ".."
import "../../Common"

// T3 Code status chip.
BarModule {
    id: t3Module

    moduleId: "t3"
    spacing: 1
    detailSaving: Settings.modOpts.t3.showLabel
        ? t3Chip.detailSaving : 0

    Divider {
        visible: t3Module.dividerBefore
    }

    T3Chip {
        id: t3Chip
        displayMode: t3Module.compact
            || !Settings.modOpts.t3.showLabel ? 0 : 2
        host: t3Module.host
        panelName: "t3code"
        isle: t3Module.isle
    }
}
