import QtQuick
import ".."
import "../../Common"

// Wi-Fi status.
BarModule {
    id: root

    moduleId: "wifi"

    BarIcon {
        id: wifiIcon

        host: root.host
        panelName: "wifi"
        isle: root.isle
        glyph: ""
        idleColor: WifiState.enabled ? (WifiState.connected ? Theme.icon : Theme.textLow) : Theme.textFaint
        tooltip: WifiState.connected ? "Wi-Fi · " + WifiState.name : "Wi-Fi"
        tooltipAlign: 1
    }
}
