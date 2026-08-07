pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "StatusHelpers.js" as StatusHelpers

// The one reading of the battery. UPower's display device is the aggregate
// the desktop is meant to show; the charge semantics come from
// StatusHelpers so bar and popover cannot drift apart again (WP1.3 fixed
// that drift in the pure logic — this is where the reactive half lands).
Singleton {
    id: root

    readonly property var device: UPower.displayDevice

    // A desktop with no battery still has a display device, so presence is
    // not enough to decide whether to draw the module.
    readonly property bool isLaptop: device !== null && device.isLaptopBattery

    readonly property real percent: StatusHelpers.batteryPercent(device)

    // "charging" | "discharging" | "full" | "" — full stays distinct from
    // charging. The bar draws both as plugged in and only its tooltip says
    // which; the popover names them apart.
    readonly property string state: StatusHelpers.chargeState(device)
    readonly property bool pluggedIn: StatusHelpers.isPluggedIn(device)
    readonly property bool charging: state === "charging"
    readonly property bool full: state === "full"
}
