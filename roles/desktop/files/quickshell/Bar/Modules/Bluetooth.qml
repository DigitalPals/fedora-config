import QtQuick
import "../../Common"

// Bluetooth, inside the status pill. The bar's auto-rule keeps it off screen
// unless something is actually connected.
BarModule {
    id: root

    moduleId: "bt"

    Sym {
        anchors.verticalCenter: parent.verticalCenter
        name: BluetoothState.enabled ? "bluetooth" : "bluetooth_disabled"
        size: Theme.barIconSize
        color: Theme.barTextHi
        opacity: BluetoothState.connected ? 1 : 0.35

        Behavior on opacity {
            NumberAnimation { duration: Theme.chipFadeDuration }
        }
    }
}
