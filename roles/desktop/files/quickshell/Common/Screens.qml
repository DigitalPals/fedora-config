pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Maps Hyprland output names to Quickshell screens. Every connected screen has
// a bar; focused is still used for keyboard/IPC overlays with no pointer-owned
// output of their own.
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

    function byName(name) {
        if (!name)
            return null;
        return Quickshell.screens.find(screen => screen.name === name) ?? null;
    }

    function hasBar(screen) {
        return screen !== null
            && Quickshell.screens.some(candidate => candidate === screen);
    }
}
