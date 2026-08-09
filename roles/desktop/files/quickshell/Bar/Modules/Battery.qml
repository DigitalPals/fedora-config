import QtQuick
import ".."
import "../../Common"

// Battery; shown only on laptops (auto-rule).
BarModule {
    id: root

    moduleId: "batt"

    BarIcon {
        id: batteryIcon

        host: root.host
        panelName: "battery"
        isle: root.isle
        visible: Battery.isLaptop
        // md-battery_high / md-battery_charging_high. The charging
        // glyph carries its own bolt, so nothing is overlaid; it is
        // also wider, hence the fixed column below, which keeps the
        // rest of the cluster still as the two swap. It was tuned as
        // 13.5 against a 14px icon, and tracks the token from there
        // so a size change cannot leave the column behind.
        glyph: Battery.pluggedIn ? "󱊦" : "󱊣"
        glyphWidth: Theme.barIconSize - 0.5
        // An empty label also zeroes BarIcon's detailSaving, so
        // fitBar never budgets for a percentage that is never shown.
        label: Settings.modOpts.batt.showPct ? Math.round(Battery.percent) + "%" : ""
        compact: root.compact
        alert: !Battery.pluggedIn && Battery.percent <= Settings.modOpts.batt.critAt
        idleColor: Battery.pluggedIn ? Theme.accent : Battery.percent <= Settings.modOpts.batt.warnAt ? Theme.amber : Theme.icon
        tooltip: "Battery " + Math.round(Battery.percent) + "%"
            + (Battery.state === "charging" ? " · charging"
                : Battery.state === "full" ? " · fully charged" : "")
        tooltipAlign: 1
    }
}
