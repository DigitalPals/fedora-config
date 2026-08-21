import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "Bar"
import "Common"
import "Common/PanelRegistryData.js" as PanelRegistry

ShellRoot {
    id: shell

    // Hyprland dispatches this in-process. Super+Space no longer waits for a
    // new `qs ipc` client process to start and connect before opening.
    GlobalShortcut {
        appid: "quickshell"
        name: "launcherToggle"
        description: "Toggle the application launcher"
        onPressed: Launcher.toggle()
    }

    // Popout IPC lives here rather than in Bar: the bar is instantiated
    // once per output, and an IpcHandler target may only be registered
    // once shell-wide.
    IpcHandler {
        target: "popouts"

        function toggle(name: string): void {
            Popouts.toggle(name);
        }

        function open(name: string): void {
            Popouts.openPanel(name);
        }

        function close(): void {
            Popouts.close();
        }
    }

    // Shell-wide because the shared settings popout can move between
    // monitor-specific bar hosts. The external IPC contract stays intact.
    IpcHandler {
        target: "settings"

        function toggle(): void {
            Settings.togglePanel();
        }

        function open(page: string): void {
            Settings.showPanel(page);
        }

        function close(): void {
            Settings.closePanel();
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

    // Timer services call this after delivering a reminder so the indicator
    // and an open manager update without waiting for their polling fallback.
    IpcHandler {
        target: "reminders"

        function refresh(): void {
            Reminders.refresh();
        }
    }

    // The two shell-wide overlays, so the compositor can bind them directly
    // rather than the shell having to own a keybind.
    IpcHandler {
        target: "session"

        function power(): void {
            Session.toggleMenu();
        }

        function keys(): void {
            Session.toggleKeys();
        }

        function lock(): void {
            Session.lock();
        }

        function close(): void {
            Session.closeAll();
        }
    }

    // A popout belongs to the bar that spawned it; when focus moves to
    // another output that bar goes away, so dismiss the panel with it.
    Connections {
        target: Screens

        function onFocusedChanged() {
            // Panels that can hand themselves to the newly live bar stay;
            // everything else belonged to the bar that just went away.
            if (!PanelRegistry.persistsAcrossHosts(Popouts.currentName))
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
            // "All" keeps today's follow-focus behavior; a pinned monitor
            // holds the bar there. A pinned name that is not currently
            // connected falls back to follow-focus so the bar never vanishes.
            readonly property bool barEnabled: {
                if (Settings.monitor === "All"
                    || !Quickshell.screens.some(s => s.name === Settings.monitor))
                    return onFocusedScreen;
                return modelData !== null && modelData.name === Settings.monitor;
            }

            Bar {
                id: bar
                screen: barScope.modelData
                visible: barScope.barEnabled
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
    PowerMenu {}
    ShortcutsOverlay {}

    // Reading a singleton's property is what constructs it. Notifications
    // must start collecting, usage and GitHub must start polling — GitHub
    // also raises the toasts for watched repositories, which must not wait
    // for the popover — and settings must load from session start rather than
    // from the first popover open.
    Component.onCompleted: {
        void Notifs.server;
        void Usage.pollIntervalSecs;
        void GitHub.pollEnabled;
        void Settings.loaded;
        void Updates.total;
        void Recorder.active;
        void Dictation.state;
        void Reminders.count;
    }
}
