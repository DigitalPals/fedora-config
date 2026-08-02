import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "Bar"
import "Common"

ShellRoot {
    id: shell

    readonly property var desiredBarScreen: Screens.focused
    property var barScreen: null

    function migrateBar() {
        if (barScreen === desiredBarScreen)
            return;
        Popouts.close();
        barScreen = desiredBarScreen;
    }

    onDesiredBarScreenChanged: migrateBar()
    Component.onCompleted: migrateBar()

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
                source: Wallpaper.current !== "" ? Wallpaper.url(Wallpaper.current) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize: Qt.size(
                    Math.ceil(modelData.width * modelData.devicePixelRatio),
                    Math.ceil(modelData.height * modelData.devicePixelRatio))
            }
        }
    }

    Bar {
        id: bar
        screen: shell.barScreen
    }

    BarPopoutWindow {
        bar: bar
        screen: shell.barScreen
    }

    LauncherWindow {}
    NotificationToasts {}

    // Touch the singletons so notifications collect and usage polls from
    // session start, not first popover open.
    readonly property var _init: [Notifs.server, Usage.pollIntervalSecs]
}
