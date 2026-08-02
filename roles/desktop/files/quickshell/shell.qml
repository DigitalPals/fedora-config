import QtQuick
import Quickshell
import Quickshell.Wayland
import "Bar"
import "Popovers"
import "Common"

ShellRoot {
    // Wallpaper on the background layer.
    PanelWindow {
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

    Bar {}

    PopoverWindow {}

    // Touch the singletons so notifications collect and usage polls from
    // session start, not first popover open.
    readonly property var _init: [Notifs.server, Usage.pollIntervalSecs]
}
