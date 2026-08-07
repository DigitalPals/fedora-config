import QtQuick
import ".."
import "../../Common"

// Bluetooth; shown only while a device is connected (auto-rule).
BarModule {
    id: root

    moduleId: "bt"

    BarIcon {
        id: btIcon

        host: root.host
        panelName: "bluetooth"
        isle: root.isle
        visible: BluetoothState.connected
        glyph: ""
        tooltip: "Bluetooth connected"
        tooltipAlign: 1
    }
}
