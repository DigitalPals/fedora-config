import QtQuick
import "../../Common"

// Combined Network status, kept under the persisted `wifi` module id. Wired
// wins the glyph while active; without it, the familiar Wi-Fi states remain.
BarModule {
    id: root

    moduleId: "wifi"

    // ModuleSlot only constructs this object for the enabled module on the
    // live bar. Its object lifetime is therefore the exact polling claim.
    Component.onCompleted: EthernetState.acquire()
    Component.onDestruction: EthernetState.release()

    Sym {
        anchors.verticalCenter: parent.verticalCenter
        name: EthernetState.connected ? "lan"
            : !WifiState.enabled ? "wifi_off"
            : !WifiState.connected ? "wifi_find"
            : WifiState.signal >= 66 ? "wifi"
            : WifiState.signal >= 33 ? "network_wifi_2_bar"
            : "network_wifi_1_bar"
        size: Theme.barIconSize
        fill: 1
        color: Theme.barTextHi
        opacity: EthernetState.connected || WifiState.connected ? 1 : 0.35

        Behavior on opacity {
            NumberAnimation { duration: Theme.chipFadeDuration }
        }
    }
}
