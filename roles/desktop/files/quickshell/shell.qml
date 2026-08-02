import QtQuick
import Quickshell
import Quickshell.Wayland
import "Bar"
import "Popovers"
import "Common"

ShellRoot {
    // Wallpaper on the background layer, one per output. Instantiated
    // through Variants so outputs appearing/disappearing (dock, lid)
    // create and destroy the windows instead of stranding them on Qt's
    // placeholder screen.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property ShellScreen modelData

            screen: modelData
            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: "#101116"

            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "qs-wallpaper"

            Image {
                anchors.fill: parent
                source: Wallpaper.current !== "" ? "file://" + Wallpaper.current : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
            }
        }
    }

    // Single bar, pinned to the first available output. The binding
    // re-evaluates when outputs change, so the bar migrates to a real
    // screen instead of staying on the placeholder.
    Bar {
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    }

    PopoverWindow {}

    // Touch the singletons so notifications collect and usage polls from
    // session start, not first popover open.
    readonly property var _init: [Notifs.server, Usage.pollIntervalSecs]
}
