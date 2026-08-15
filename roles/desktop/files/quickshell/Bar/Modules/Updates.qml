import QtQuick
import ".."
import "../../Common"

// Pending updates. The bar's auto-rule hides this module while a completed
// check has nothing to report, but leaves failures and manual rechecks visible
// so the user is never locked out of recovery.
BarModule {
    id: root

    moduleId: "updates"
    detailSaving: chip.detailSaving

    BarIcon {
        id: chip
        host: root.host
        panelName: "updates"
        isle: root.isle
        anchorItem: root.groupAnchor ?? chip
        glyph: "deployed_code_update"
        glyphSize: Theme.barIconSize - 1
        glyphWeight: 600
        idleColor: Theme.textMid
        label: Updates.busy ? "…" : Updates.error !== "" ? "!" : Updates.total
        compact: root.compact
        labelColor: Theme.textMid
        alert: Updates.error !== ""
        tooltip: "Updates · " + Updates.summary
        tooltipAlign: 1
    }
}
