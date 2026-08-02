pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    property bool dnd: false
    // Bounded session history, newest first. Fields are copied so history
    // remains readable after the remote notification object expires.
    property var entries: []
    property var toasts: []
    readonly property int count: entries.length
    readonly property bool hasUrgent: entries.some(e => e.urgency === NotificationUrgency.Critical)

    onDndChanged: {
        if (!dnd)
            return;
        const visible = toasts.slice();
        toasts = [];
        for (const entry of visible) {
            if (entry.live && entry.notif)
                entry.notif.expire();
        }
    }

    function updateEntry(key, changes) {
        entries = entries.map(entry => entry.key === key ? Object.assign({}, entry, changes) : entry);
        toasts = toasts.map(entry => entry.key === key ? Object.assign({}, entry, changes) : entry);
    }

    function removeEntry(key) {
        entries = entries.filter(entry => entry.key !== key);
        toasts = toasts.filter(entry => entry.key !== key);
    }

    function hideToast(entry, expireRemote) {
        toasts = toasts.filter(item => item.key !== entry.key);
        if (expireRemote && entry.live && entry.notif)
            entry.notif.expire();
    }

    function dismiss(entry) {
        removeEntry(entry.key);
        if (entry.live && entry.notif)
            entry.notif.dismiss();
    }

    function invoke(entry, action) {
        if (!entry.live || !action)
            return;
        action.invoke();
        hideToast(entry, false);
    }

    function timeoutFor(entry) {
        if (entry.expireTimeout > 0 && entry.expireTimeout <= 120)
            return Math.round(entry.expireTimeout * 1000);
        return entry.urgency === NotificationUrgency.Critical ? 8000 : 5000;
    }

    readonly property NotificationServer server: NotificationServer {
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: notif => {
            notif.tracked = true;
            const arrived = Date.now();
            const entry = {
                key: `${notif.id}-${arrived}`,
                notif: notif,
                live: true,
                arrived: arrived,
                appName: notif.appName,
                appIcon: notif.appIcon,
                summary: notif.summary,
                body: notif.body,
                urgency: notif.urgency,
                expireTimeout: notif.expireTimeout,
                actions: notif.actions
            };
            const evicted = root.entries.slice(49);
            root.entries = [entry].concat(root.entries.slice(0, 49));
            for (const old of evicted) {
                if (old.live && old.notif)
                    old.notif.expire();
            }
            if (!root.dnd && !notif.lastGeneration) {
                const dropped = root.toasts.slice(2);
                root.toasts = [entry].concat(root.toasts.slice(0, 2));
                for (const old of dropped) {
                    if (old.live && old.notif)
                        old.notif.expire();
                }
            }
            notif.closed.connect(() => {
                root.updateEntry(entry.key, { live: false, notif: null, actions: [] });
                root.toasts = root.toasts.filter(item => item.key !== entry.key);
            });
        }
    }

    function clearAll() {
        const list = entries.slice();
        entries = [];
        toasts = [];
        for (const entry of list) {
            if (entry.live && entry.notif)
                entry.notif.dismiss();
        }
    }

    function timeAgo(arrived, now) {
        const s = Math.max(0, ((now || Date.now()) - arrived) / 1000);
        if (s < 60)
            return "now";
        if (s < 3600)
            return Math.floor(s / 60) + "m";
        if (s < 86400)
            return Math.floor(s / 3600) + "h";
        return Math.floor(s / 86400) + "d";
    }
}
