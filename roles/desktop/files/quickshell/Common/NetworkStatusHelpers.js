// Pure parsing for Common/NetworkStatus.qml. `nmcli --get-values STATE`
// deliberately uses NetworkManager's overall state: unlike the state of one
// device, it only says "connected" when the machine has global connectivity.

function onlineState(text) {
    if (typeof text !== "string")
        return null;

    var state = text.trim().toLowerCase();
    if (state === "connected" || state === "connected (global)")
        return true;

    var offline = [
        "unknown",
        "asleep",
        "disconnected",
        "disconnecting",
        "connecting",
        "connected (local only)",
        "connected (site only)"
    ];
    return offline.indexOf(state) !== -1 ? false : null;
}

var exported = { onlineState: onlineState };

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
