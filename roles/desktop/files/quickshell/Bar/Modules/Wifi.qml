import QtQuick
import "../../Common"

// Wi-Fi, inside the status pill. Dimmed rather than hidden while the radio is
// off or unassociated: an absent icon says nothing, a faded one says the radio
// is there and idle.
BarModule {
    id: root

    moduleId: "wifi"

    Sym {
        anchors.verticalCenter: parent.verticalCenter
        name: !WifiState.enabled ? "wifi_off"
            : !WifiState.connected ? "wifi_find"
            : WifiState.signal >= 66 ? "wifi"
            : WifiState.signal >= 33 ? "network_wifi_2_bar"
            : "network_wifi_1_bar"
        size: Theme.barIconSize
        fill: 1
        color: Theme.textHi
        opacity: WifiState.enabled && WifiState.connected ? 1 : 0.35

        Behavior on opacity {
            NumberAnimation { duration: Theme.chipFadeDuration }
        }
    }
}
