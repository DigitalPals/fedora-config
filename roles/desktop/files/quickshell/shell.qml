import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Bar"
import "Common"

ShellRoot {
    id: shell

    // Popout IPC lives here rather than in Bar: the bar is instantiated
    // once per output, and an IpcHandler target may only be registered
    // once shell-wide.
    IpcHandler {
        target: "popouts"

        function toggle(name: string): void {
            Popouts.toggle(name);
        }

        function close(): void {
            Popouts.close();
        }
    }

    // Pinged by brightness-control after brightnessctl runs; volume needs
    // no IPC because the OSD watches Pipewire directly.
    IpcHandler {
        target: "osd"

        function brightness(): void {
            Osd.brightnessChanged();
        }
    }

    // A popout belongs to the bar that spawned it; when focus moves to
    // another output that bar goes away, so dismiss the panel with it.
    Connections {
        target: Screens

        function onFocusedChanged() {
            Popouts.close();
        }
    }

    // Wallpaper on the background layer, one per output. Instantiated
    // through Variants so outputs appearing/disappearing (dock, lid)
    // create and destroy the windows instead of stranding them on Qt's
    // placeholder screen.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: wallpaperWindow

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
                // modelData is briefly null while an output is torn down;
                // 0 falls back to the image's own size for that instant.
                sourceSize.width: wallpaperWindow.modelData
                    ? Math.ceil(wallpaperWindow.modelData.width * wallpaperWindow.modelData.devicePixelRatio) : 0
                sourceSize.height: wallpaperWindow.modelData
                    ? Math.ceil(wallpaperWindow.modelData.height * wallpaperWindow.modelData.devicePixelRatio) : 0
            }
        }
    }

    // The bar shows on one output at a time, but it is built per output
    // and only shown on the focused one. The bar used to be a single
    // window whose `screen` was reassigned on focus change, and it could
    // end up unmapped after a hotplug or after external-monitor-toggle
    // disabled eDP-1. Binding each window to one output for its lifetime
    // removes the migration entirely: outputs coming and going create and
    // destroy windows, exactly as the wallpaper above already does.
    Variants {
        model: Quickshell.screens

        Scope {
            id: barScope

            required property ShellScreen modelData
            readonly property bool onFocusedScreen: modelData !== null && modelData === Screens.focused

            Bar {
                id: bar
                screen: barScope.modelData
                visible: barScope.onFocusedScreen
            }

            BarPopoutWindow {
                bar: bar
                screen: barScope.modelData
            }
        }
    }

    LauncherWindow {}
    NotificationToasts {}
    OsdWindow {}

    // Touch the singletons so notifications collect and usage polls from
    // session start, not first popover open.
    readonly property var _init: [Notifs.server, Usage.pollIntervalSecs]
}
