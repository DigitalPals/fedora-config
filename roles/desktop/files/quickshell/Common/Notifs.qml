pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "NotifHelpers.js" as Helpers
import "SettingsHelpers.js" as SettingsHelpers
import "Format.js" as Format

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

    // Serial for keys of shell-originated notifications, which have no
    // D-Bus id to key on.
    property int localSerial: 0

    // The one place an entry is built and bounded, so a shell-originated
    // notification is presented exactly like a D-Bus one. `notif` is null for
    // shell senders: no remote object, no actions, which the rest of this file
    // already treats as an expired entry (see dismiss/hideToast/iconSource).
    function publish(source, notif) {
        const arrived = Date.now();
        const hints = Object.assign({}, source.hints || {});
        const presentation = Helpers.derivePresentation({
            appName: source.appName,
            desktopEntry: source.desktopEntry,
            summary: source.summary,
            body: source.body,
            hints: hints
        });
        const requestedBrand = BrandIcons.has(source.brandIcon)
            ? BrandIcons.key(source.brandIcon) : "";
        const derivedBrand = BrandIcons.has(presentation.brandIcon)
            ? BrandIcons.key(presentation.brandIcon) : "";
        const entry = {
            key: notif ? `${notif.id}-${arrived}` : `shell-${++localSerial}-${arrived}`,
            notif: notif ?? null,
            live: !!notif,
            arrived: arrived,
            appName: source.appName ?? "",
            appIcon: source.appIcon ?? "",
            desktopEntry: source.desktopEntry ?? "",
            hints: hints,
            image: source.image ?? "",
            summary: source.summary ?? "",
            body: source.body ?? "",
            displayAppName: presentation.displayAppName,
            displaySummary: presentation.displaySummary,
            displayBody: presentation.displayBody,
            webOrigin: presentation.webOrigin,
            brandIcon: requestedBrand !== "" ? requestedBrand : derivedBrand,
            urgency: source.urgency ?? NotificationUrgency.Normal,
            expireTimeout: source.expireTimeout ?? -1,
            actions: notif ? notif.actions : []
        };
        const evicted = entries.slice(49);
        entries = [entry].concat(entries.slice(0, 49));
        for (const old of evicted) {
            if (old.live && old.notif)
                old.notif.expire();
        }
        if (!toastsSuppressed && !(notif && notif.lastGeneration)) {
            const dropped = toasts.slice(2);
            toasts = [entry].concat(toasts.slice(0, 2));
            for (const old of dropped) {
                if (old.live && old.notif)
                    old.notif.expire();
            }
        }
        return entry;
    }

    // Single in-shell path for notifications the shell raises itself. Going
    // out to `notify-send` and back in over D-Bus costs a process per toast
    // and only honours DND/quiet hours by accident of this shell owning
    // org.freedesktop.Notifications. Suppressed sends still reach the
    // notification center, exactly as a remote notification would.
    function send(request) {
        const options = request ?? {};
        return publish({
            appName: options.appName || "Shell",
            appIcon: options.appIcon ?? "",
            desktopEntry: options.desktopEntry ?? "",
            brandIcon: options.brandIcon ?? "",
            image: options.image ?? "",
            summary: options.summary ?? "",
            body: options.body ?? "",
            urgency: options.urgency,
            expireTimeout: options.expireTimeout
        }, null).key;
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
            const entry = root.publish({
                appName: notif.appName,
                appIcon: notif.appIcon,
                desktopEntry: notif.desktopEntry,
                hints: notif.hints,
                image: notif.image,
                summary: notif.summary,
                body: notif.body,
                urgency: notif.urgency,
                expireTimeout: notif.expireTimeout
            }, notif);
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

    // Image source for the non-brand half of an entry's icon slot; NotifIcon
    // renders an approved brand name through BrandIcon before calling here.
    // Every step falls through when it cannot produce something loadable.
    // Browser notifications exclude the browser logo once an origin is known
    // and use the site's notification image here. NotifIcon adds the browser's
    // cached favicon and remote /favicon.ico fallbacks before its web glyph.
    // Native applications use app icon, desktop entry, attached image, then
    // their glyph fallback.
    function iconSource(entry) {
        let source = "";
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
        if (s < Format.MINUTE)
            return "now";
        if (s < Format.HOUR)
            return Math.floor(s / Format.MINUTE) + "m";
        if (s < Format.DAY)
            return Math.floor(s / Format.HOUR) + "h";
        return Math.floor(s / Format.DAY) + "d";
    }
}
