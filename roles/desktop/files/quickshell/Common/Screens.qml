pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Maps Hyprland's focused output to the corresponding Quickshell screen.
// Keeping this in one place makes the bar, launcher, and notification toasts
// agree during focus changes and monitor hotplug.
Singleton {
    id: root

    readonly property var focused: {
        const screens = Quickshell.screens;
        const monitor = Hyprland.focusedMonitor;
        if (monitor !== null) {
            const match = screens.find(screen => screen.name === monitor.name);
            if (match !== undefined)
                return match;
        }
        return screens.length > 0 ? screens[0] : null;
    }
}
