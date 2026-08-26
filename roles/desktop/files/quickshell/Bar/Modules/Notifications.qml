import QtQuick
import ".."
import "../../Common"

// Retained session notification history. Opening the panel is intentionally
// read-only: dismissing a card or clearing the history is what lowers count.
BarModule {
    id: root

    moduleId: "notifications"
    detailSaving: chip.detailSaving

    BarIcon {
        id: chip

        host: root.host
        panelName: "notifications"
        isle: root.isle
        anchorItem: root.groupAnchor ?? chip
        glyph: Notifs.dnd ? "notifications_off" : "notifications"
        glyphSize: Theme.barIconSize
        glyphFill: Notifs.dnd || Notifs.hasUrgent ? 1 : 0
        glyphWeight: 550
        label: Notifs.count > 99 ? "99+" : String(Notifs.count)
        compact: root.compact
        // Critical history stays visible even while DND suppresses its toast.
        alert: Notifs.hasUrgent
        active: Notifs.dnd && !Notifs.hasUrgent
        tooltip: Notifs.dnd
            ? "Notifications · Do Not Disturb · " + Notifs.count
            : Notifs.count === 1 ? "1 notification"
            : Notifs.count + " notifications"
        tooltipAlign: 1
    }
}
