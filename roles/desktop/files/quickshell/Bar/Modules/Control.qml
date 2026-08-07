import QtQuick
import ".."
import "../../Common"

// Control Center launcher.
BarModule {
    id: root

    moduleId: "control"

    BarIcon {
        id: controlIcon

        host: root.host
        panelName: "control"
        isle: root.isle
        glyph: "\uf30a" // fedora logo — Control Center trigger
        glyphSize: Theme.barIconSize
        active: root.host !== null && root.host.popoutOpen("control")
        tooltip: "Control Center"
        tooltipAlign: 1
    }
}
