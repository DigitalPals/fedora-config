import QtQuick
import ".."
import "../../Common"

// Keep-awake toggle. No popout, so it owns no panel.
BarModule {
    id: idleModule

    moduleId: "idle"
    spacing: 1

    Divider {
        visible: idleModule.dividerBefore
    }

    // Keep-awake toggle. Lit while inhibiting; no popout, so
    // it deliberately skips the hover-switch wiring.
    BarIcon {
        glyph: "" // coffee
        active: SysInfo.idleInhibited
        idleColor: Theme.textLow
        tooltip: SysInfo.idleInhibited ? "Idle inhibit on" : "Idle inhibit off"
        tooltipAlign: 1
        onClicked: SysInfo.idleInhibited = !SysInfo.idleInhibited
    }
}
