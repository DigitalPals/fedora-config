pragma Singleton
import QtQuick
import Quickshell

// Session actions used by the Control Panel and the keyboard cheatsheet
// reachable from its footer or Super+K.
Singleton {
    id: root

    property bool keysOpen: false
    property var screen: null

    readonly property string lockCommand:
        "hyprlock --config " + Quickshell.env("HOME")
        + "/.config/hypr/hyprlock.conf --immediate-render --no-fade-in"

    function openKeys(targetScreen) {
        const popoutScreen = Screens.byName(Popouts.hostScreenName);
        screen = targetScreen ?? popoutScreen ?? Screens.focused;
        Popouts.close();
        Launcher.close();
        keysOpen = true;
    }

    function closeKeys() {
        keysOpen = false;
    }

    function toggleKeys(targetScreen) {
        if (keysOpen)
            closeKeys();
        else
            openKeys(targetScreen);
    }

    function closeAll() {
        keysOpen = false;
    }

    function run(command) {
        closeAll();
        Quickshell.execDetached(["sh", "-c", command]);
    }

    function lock() {
        run(lockCommand);
    }

    function suspend() {
        // Lock first: waking to an unlocked session is the one outcome none of
        // these buttons should ever produce.
        run(lockCommand + " & sleep 0.3; systemctl suspend");
    }

    function reboot() {
        run("systemctl reboot");
    }

    function shutdown() {
        run("systemctl poweroff");
    }

    function logout() {
        run("hyprctl dispatch exit");
    }

    // The rows the cheatsheet draws. Kept here rather than in the overlay so
    // the list is data the Control Panel could also summarise, and so it
    // stays next to the actions it documents.
    readonly property var shortcutGroups: [
        {
            title: "SHELL",
            rows: [
                { label: "Launcher", keys: ["Super", "Space"] },
                { label: "Notifications", keys: ["Super", "N"] },
                { label: "Control Panel", keys: ["Super", "A"] },
                { label: "Shell settings", keys: ["Super", ","] },
                { label: "T3 Code", keys: ["Super", "T"] },
                { label: "Lock", keys: ["Super", "L"] },
                { label: "This overlay", keys: ["Super", "K"] }
            ]
        },
        {
            title: "WINDOWS",
            rows: [
                { label: "Close window", keys: ["Super", "Q"] },
                { label: "Toggle float", keys: ["Super", "F"] },
                { label: "Toggle split", keys: ["Super", "J"] },
                { label: "Focus", keys: ["Super", "←", "→"] },
                { label: "Fade window", keys: ["Super", "Backspace"] }
            ]
        },
        {
            title: "WORKSPACES",
            rows: [
                { label: "Switch", keys: ["Super", "1…9"] },
                { label: "Send window", keys: ["Super", "Shift", "1…9"] },
                { label: "Cycle", keys: ["Super", "Scroll"] }
            ]
        },
        {
            title: "CAPTURE & MEDIA",
            rows: [
                { label: "Region screenshot", keys: ["Print"] },
                { label: "Whole screen", keys: ["Shift", "Print"] },
                { label: "Record screen", keys: ["Super", "Shift", "`"] },
                { label: "OCR a region", keys: ["Super", "Shift", "O"] },
                { label: "Volume · brightness", keys: ["Fn"] }
            ]
        }
    ]
}
