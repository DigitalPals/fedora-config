pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    property bool dnd: false
    // [{notif, arrived}] newest first
    property var entries: []
    readonly property int count: entries.length
    readonly property bool hasUrgent: entries.some(e => e.notif.urgency === NotificationUrgency.Critical)

    readonly property NotificationServer server: NotificationServer {
        keepOnReload: true
        bodySupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: notif => {
            notif.tracked = true;
            root.entries = [{ notif: notif, arrived: Date.now() }].concat(root.entries);
            notif.closed.connect(() => {
                root.entries = root.entries.filter(e => e.notif !== notif);
            });
        }
    }

    function clearAll() {
        const list = entries.slice();
        for (const e of list)
            e.notif.dismiss();
        entries = [];
    }

    function timeAgo(arrived) {
        const s = Math.max(0, (Date.now() - arrived) / 1000);
        if (s < 60)
            return "now";
        if (s < 3600)
            return Math.floor(s / 60) + "m";
        if (s < 86400)
            return Math.floor(s / 3600) + "h";
        return Math.floor(s / 86400) + "d";
    }
}
