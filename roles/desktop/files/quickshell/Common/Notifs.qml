pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "NotifHelpers.js" as Helpers
import "SettingsHelpers.js" as SettingsHelpers

Singleton {
    id: root

    // Do Not Disturb persists with the shell settings; quiet hours silence
    // toasts on a schedule the same way. Both only gate the popup — every
    // notification still lands in the center.
    readonly property bool dnd: Settings.notifDnd
    readonly property bool quietActive: SettingsHelpers.quietActive(Settings.notifQuiet,
        Settings.notifQuietStart, Settings.notifQuietEnd,
        quietClock.date.getHours() * 60 + quietClock.date.getMinutes())
    readonly property bool toastsSuppressed: dnd || quietActive
    // Bounded session history, newest first. Fields are copied so history
    // remains readable after the remote notification object expires.
    property var entries: []
    property var toasts: []
    readonly property int count: entries.length
    readonly property bool hasUrgent: entries.some(e => e.urgency === NotificationUrgency.Critical)

    function setDnd(value) {
        Settings.set("notifDnd", value);
    }

    SystemClock {
        id: quietClock
        precision: SystemClock.Minutes
    }

    onToastsSuppressedChanged: {
        if (!toastsSuppressed)
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

    function defaultAction(entry) {
        return entry && entry.live ? Helpers.defaultAction(entry.actions) : null;
    }

    function secondaryActions(entry) {
        return entry && entry.live ? Helpers.secondaryActions(entry.actions) : [];
    }

    function canActivate(entry) {
        return defaultAction(entry) !== null;
    }

    function invokeDefault(entry) {
        const action = defaultAction(entry);
        if (action)
            invoke(entry, action);
    }

    // Critical toasts never reach this: they persist until dismissed
    // (design t4), so only normal urgencies deplete.
    function timeoutFor(entry) {
        return Helpers.timeoutMs(Helpers.visibleCharacterCount(entry),
            entry.expireTimeout, Settings.notifDuration * 1000);
    }

    readonly property NotificationServer server: NotificationServer {
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        extraHints: ["x-kde-origin-name"]

        onNotification: notif => {
            notif.tracked = true;
            // Keep this: icon-resolution misses are impossible to diagnose
            // after the fact without knowing what the sender actually sent.
            console.log(`notification: app="${notif.appName}" desktop="${notif.desktopEntry}" icon="${notif.appIcon}" image="${notif.image}"`);
            const arrived = Date.now();
            const hints = Object.assign({}, notif.hints || {});
            const presentation = Helpers.derivePresentation({
                appName: notif.appName,
                desktopEntry: notif.desktopEntry,
                summary: notif.summary,
                body: notif.body,
                hints: hints
            });
            const entry = {
                key: `${notif.id}-${arrived}`,
                notif: notif,
                live: true,
                arrived: arrived,
                appName: notif.appName,
                appIcon: notif.appIcon,
                desktopEntry: notif.desktopEntry,
                hints: hints,
                image: notif.image,
                summary: notif.summary,
                body: notif.body,
                displayAppName: presentation.displayAppName,
                displaySummary: presentation.displaySummary,
                displayBody: presentation.displayBody,
                webOrigin: presentation.webOrigin,
                brandIcon: presentation.brandIcon === "whatsapp"
                    ? Quickshell.shellDir + "/assets/whatsapp.svg" : "",
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
            if (!root.toastsSuppressed && !notif.lastGeneration) {
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
    function entryIcon(identity) {
        if (!identity)
            return "";
        const entry = DesktopEntries.heuristicLookup(identity)
            || DesktopEntries.heuristicLookup(identity.toLowerCase().replace(/\s+/g, "-"));
        if (entry && entry.icon)
            return entry.icon;
        const lower = identity.toLowerCase();
        const byName = DesktopEntries.applications.values.find(e => e.name && e.name.toLowerCase() === lower);
        return byName && byName.icon ? byName.icon : "";
    }

    function resolvedIcon(value) {
        if (!value)
            return "";
        if (value.startsWith("/"))
            return "file://" + value;
        if (value.startsWith("file://") || value.startsWith("data:")
                || value.startsWith("qrc:") || value.startsWith("image://"))
            return value;
        const themed = Quickshell.iconPath(value, true);
        return themed !== "" ? themed : "";
    }

    // Image source for an entry's icon slot. Every step falls through when
    // it cannot produce something loadable. Once a browser notification has
    // a web origin, its browser logo is deliberately excluded: a known brand
    // wins, followed by the site's supplied image and the web glyph fallback.
    // Native applications use app icon, desktop entry, attached image, glyph.
    function iconSource(entry) {
        let source = resolvedIcon(entry.brandIcon || "");
        if (source !== "")
            return source;
        if (entry.webOrigin) {
            source = resolvedIcon(entry.image || "");
            return source;
        }
        source = resolvedIcon(entry.appIcon || "");
        if (source !== "")
            return source;
        const named = entryIcon(entry.desktopEntry || entry.appName);
        if (named !== "") {
            source = resolvedIcon(named);
            if (source !== "")
                return source;
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
