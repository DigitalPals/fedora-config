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

    // Critical toasts never reach this: they persist until dismissed
    // (design t4), so only normal urgencies deplete.
    function timeoutFor(entry) {
        if (entry.expireTimeout > 0 && entry.expireTimeout <= 120)
            return Math.round(entry.expireTimeout * 1000);
        return 6000;
    }

    readonly property NotificationServer server: NotificationServer {
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: notif => {
            notif.tracked = true;
            // Keep this: icon-resolution misses are impossible to diagnose
            // after the fact without knowing what the sender actually sent.
            console.log(`notification: app="${notif.appName}" icon="${notif.appIcon}" image="${notif.image}"`);
            const arrived = Date.now();
            const entry = {
                key: `${notif.id}-${arrived}`,
                notif: notif,
                live: true,
                arrived: arrived,
                appName: notif.appName,
                appIcon: notif.appIcon,
                image: notif.image,
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

    // Resolve an app's desktop-entry icon from the appName a notification
    // carries. Senders write anything from exact ids ("google-chrome") to
    // display names ("Google Chrome", "Firefox"), so try the id heuristic,
    // a dashed lowercase form, and finally the entries' display names.
    function entryIcon(appName) {
        if (!appName)
            return "";
        const entry = DesktopEntries.heuristicLookup(appName)
            || DesktopEntries.heuristicLookup(appName.toLowerCase().replace(/\s+/g, "-"));
        if (entry && entry.icon)
            return entry.icon;
        const lower = appName.toLowerCase();
        const byName = DesktopEntries.applications.values.find(e => e.name && e.name.toLowerCase() === lower);
        return byName && byName.icon ? byName.icon : "";
    }

    // Image source for an entry's icon slot. Every step falls through when
    // it cannot produce something loadable: the appIcon hint (a theme icon
    // name, or a file path some apps send), then the app's desktop-entry
    // icon, then the notification's own image (e.g. Chrome sends the site
    // favicon). "" means: show the glyph fallback.
    function iconSource(entry) {
        const hint = entry.appIcon || "";
        if (hint) {
            if (hint.startsWith("/"))
                return "file://" + hint;
            if (hint.startsWith("file://") || hint.startsWith("data:"))
                return hint;
            const themed = Quickshell.iconPath(hint, true);
            if (themed !== "")
                return themed;
        }
        const named = entryIcon(entry.appName);
        if (named !== "") {
            const themed = Quickshell.iconPath(named, true);
            if (themed !== "")
                return themed;
        }
        return entry.image || "";
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
