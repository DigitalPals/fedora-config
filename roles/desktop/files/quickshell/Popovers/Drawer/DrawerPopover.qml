pragma ComponentBehavior: Bound
import QtQuick
import "../../Common"
import "../../Common/PanelRegistryData.js" as PanelRegistry
import ".."

// The edge drawer: the one surface every status glyph opens, per the 2026-09
// redesign (Claude Design project 8cf85161, direction 2). A tab strip —
// Overview · Sound · Network · Power · Notifications · Usage — sits above the
// tab body; the popout host attaches the surface flush under the bar and pins
// it to the right screen edge (PanelRegistryData `attached` + `edge`).
//
// Each established popout name (control, audio, wifi, battery, notifications,
// usage, …) presents one tab of this same component, so IPC names, the bar's
// held states and hover-crossing all keep working unchanged. The host keys
// its slots by source, so every one of those names reuses this same instance
// and a tab switch swaps content in place instead of cross-fading a clone.
Surface {
    id: root

    property string tab: "overview"
    // Deep links: the updates chip opens Overview with its updates row lit.
    property string highlight: ""

    padding: Theme.panelPadding
    spacing: Theme.scaled(14)
    implicitWidth: Theme.drawerWidth

    Component.onCompleted: {
        const name = Popouts.currentName;
        tab = PanelRegistry.drawerTab(name) || "overview";
        if (name === "updates")
            highlight = "updates";
    }

    // Follow the presenting name while it is a drawer name. When another
    // surface takes over (drawerTab resolves to ""), this instance is the
    // outgoing half of a cross-fade and must keep showing what it showed.
    Connections {
        target: Popouts

        function onChanged() {
            if (!Popouts.open)
                return;
            const tab = PanelRegistry.drawerTab(Popouts.currentName);
            if (tab === "")
                return;
            root.tab = tab;
            root.highlight = Popouts.currentName === "updates" ? "updates" : "";
        }
    }

    DrawerTabs {
        width: parent.width
        current: root.tab
    }

    Loader {
        width: parent.width
        sourceComponent: root.tab === "sound" ? soundTab
            : root.tab === "network" ? networkTab
            : root.tab === "power" ? powerTab
            : root.tab === "notifications" ? notificationsTab
            : root.tab === "usage" ? usageTab
            : overviewTab
    }

    Component {
        id: overviewTab
        DrawerOverview {
            highlightUpdates: root.highlight === "updates"
        }
    }

    Component {
        id: soundTab
        DrawerSound {}
    }

    Component {
        id: networkTab
        DrawerNetwork {}
    }

    Component {
        id: powerTab
        DrawerPower {}
    }

    Component {
        id: notificationsTab
        DrawerNotifications {}
    }

    Component {
        id: usageTab
        DrawerUsage {}
    }
}
