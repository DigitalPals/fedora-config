import QtQuick
import ".."

// Workspace pips.
BarModule {
    id: root

    moduleId: "ws"

    Workspaces {
        property string isle: "left"
        host: root.host
    }
}
