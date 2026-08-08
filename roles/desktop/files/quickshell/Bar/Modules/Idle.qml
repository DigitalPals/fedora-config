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

    // Keep-awake toggle. Lit while inhibiting; no popout, so it owns no
    // panel name and never joins the hover-switch. `host` is still needed:
    // it is what the tooltip validates its hover against, and without it a
    // missed exit event leaves the tip on screen indefinitely.
    BarIcon {
        host: idleModule.host
        glyph: "" // coffee
        active: SysInfo.idleInhibited
        idleColor: Theme.textLow
        tooltip: SysInfo.idleInhibited ? "Idle inhibit on" : "Idle inhibit off"
        tooltipAlign: 1
        onClicked: SysInfo.idleInhibited = !SysInfo.idleInhibited
    }
}
