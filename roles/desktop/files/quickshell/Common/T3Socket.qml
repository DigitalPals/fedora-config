import QtQuick
import QtWebSockets

// Thin WebSocket wrapper loaded dynamically by T3Code so a machine
// without the QtWebSockets QML module (qt6-qtwebsockets-devel) degrades
// to an offline chip instead of taking down the whole shell.
Item {
    id: root

    property string url: ""
    property bool active: false

    // Mirrors WebSocket.status without leaking the enum import upstream:
    // 0 connecting · 1 open · 2 closing · 3 closed · 4 error
    readonly property int status: sock.status
    readonly property bool open: sock.status === WebSocket.Open
    readonly property string errorString: sock.errorString

    signal textReceived(string message)

    function sendText(message) {
        if (sock.status === WebSocket.Open)
            sock.sendTextMessage(message);
    }

    WebSocket {
        id: sock
        url: root.url
        active: root.active
        onTextMessageReceived: message => root.textReceived(message)
    }
}
