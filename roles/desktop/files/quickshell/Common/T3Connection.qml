pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "T3CodeHelpers.js" as Helpers

// The transport half of the T3 client: the paired state file, the ticket
// exchange, the WebSocket itself, and the retry/backoff that ties them
// together. It knows nothing about the protocol spoken over the socket —
// T3Code owns that and listens to `message`.
//
// Auth model: `scripts/t3-pair.py <pairing-url>` exchanges a one-time pairing
// code for a ~30-day bearer token stored in ~/.local/state/t3code-bar.json.
// Each (re)connect trades that token for a 5-minute wsTicket over HTTP, then
// opens wss://…/ws?wsTicket=….
Singleton {
    id: root

    // "unpaired" | "connecting" | "connected" | "offline"
    property string state: "offline"
    // Why the last attempt failed, already shortened for a tooltip. Both hops
    // of connect() fill it — the ticket request and the socket — because a
    // dead host fails the first one and never reaches the second. Empty means
    // "nothing worth showing", which leaves every consumer on its generic
    // offline wording; consumers must also ignore it while unpaired, where
    // the missing token, not the network, is the story.
    property string connectionError: ""
    // The one offline state no retry can end: the WebSocket component itself
    // failed to load. Consumers use it to drop any "retrying" wording, which
    // would be a lie here — connect() deliberately arms no timer for it.
    readonly property bool websocketsMissing: socketLoader.status === Loader.Error

    property string host: ""            // https base url from the state file
    property string accessToken: ""
    readonly property bool paired: host !== "" && accessToken !== ""

    property string environmentLabel: ""
    property string environmentId: ""
    property string serverVersion: ""
    property var environmentCapabilities: ({})

    // Scope is persisted by t3-pair.py. Older state files do not contain it;
    // absence deliberately keeps the old "let the server authorize" behavior.
    property bool scopeMetadataKnown: false
    property var tokenScope: ""

    // What this token is allowed to do. Derived here because the scope comes
    // off the pairing file, and because "can dispatch" also needs the live
    // socket state — both of which are this file's business.
    readonly property var scopeInfo: Helpers.normalizeScopes(tokenScope, scopeMetadataKnown)
    readonly property bool canRead: scopeInfo.canRead
    readonly property bool canOperate: scopeInfo.canOperate
    readonly property bool readOnly: scopeMetadataKnown && !canOperate
    readonly property bool canDispatch: canOperate && state === "connected"

    // Every frame the server sends, verbatim. T3Code parses it.
    signal message(string text)
    // The socket just opened: the protocol layer resubscribes here.
    signal opened()
    // The link is going away and a retry is being armed. The protocol layer
    // fails its in-flight work here; this fires before the retry is scheduled.
    signal dropped()

    // ---- state file ------------------------------------------------------

    FileView {
        id: stateFile
        path: Quickshell.env("HOME") + "/.local/state/t3code-bar.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.host = (stateData.httpBaseUrl ?? "").replace(/\/+$/, "");
            root.accessToken = stateData.accessToken ?? "";
            root.scopeMetadataKnown = typeof stateData.scope === "string"
                || Array.isArray(stateData.scope);
            root.tokenScope = root.scopeMetadataKnown ? stateData.scope : "";
            if (root.paired)
                root.connect();
            else
                root.state = "unpaired";
        }
        onLoadFailed: root.state = "unpaired"

        JsonAdapter {
            id: stateData
            property string httpBaseUrl: ""
            property string accessToken: ""
            property var scope: null
        }
    }

    // ---- connection ------------------------------------------------------

    property int retrySecs: 5

    function connect() {
        if (!paired) {
            state = "unpaired";
            return;
        }
        // The state file routinely loads before the socket component does.
        // Without a retry the shell would sit offline until a restart; the
        // loader's onStatusChanged connects the moment it wins that race and
        // cancels the pending retry so the two never race each other. A load
        // *error* is permanent (QtWebSockets missing) and not worth retrying.
        if (socketLoader.status !== Loader.Ready) {
            state = "offline";
            if (socketLoader.status !== Loader.Error)
                scheduleRetry();
            return;
        }
        state = "connecting";
        fetchDescriptor();
        const xhr = new XMLHttpRequest();
        xhr.open("POST", host + "/api/auth/websocket-ticket");
        xhr.setRequestHeader("Authorization", "Bearer " + accessToken);
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status === 200) {
                try {
                    const ticket = JSON.parse(xhr.responseText).ticket;
                    openSocket(ticket);
                    return;
                } catch (e) {
                    console.warn("t3code: bad ticket response");
                    root.connectionError = "Malformed ticket response";
                }
            } else if (xhr.status === 401 || xhr.status === 403) {
                // Token expired or revoked: needs a fresh pairing URL.
                root.state = "unpaired";
                return;
            } else {
                root.connectionError = Helpers.ticketErrorText(xhr.status);
            }
            root.scheduleRetry();
        };
        xhr.send();
    }

    function openSocket(ticket) {
        const sock = socketLoader.item;
        sock.active = false;
        sock.url = host.replace(/^https:/, "wss:").replace(/^http:/, "ws:")
            + "/ws?wsTicket=" + encodeURIComponent(ticket);
        sock.active = true;
    }

    function fetchDescriptor() {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", host + "/.well-known/t3/environment");
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200)
                return;
            try {
                const d = JSON.parse(xhr.responseText);
                root.environmentId = d.environmentId ?? "";
                root.environmentLabel = d.label ?? "";
                root.serverVersion = typeof d.serverVersion === "string"
                    ? d.serverVersion : root.serverVersion;
                if (d.capabilities && typeof d.capabilities === "object")
                    root.environmentCapabilities = Object.assign({}, d.capabilities);
            } catch (e) {
                // Optional metadata: the shell works without it, and the
                // connection attempt this rode along with reports its own
                // failures. Worth a line so a malformed descriptor is not
                // completely silent.
                console.warn("t3code: unreadable environment descriptor:", e);
            }
        };
        xhr.send();
    }

    function scheduleRetry() {
        dropped();
        if (socketLoader.item)
            socketLoader.item.active = false;
        if (state !== "unpaired")
            state = "offline";
        retryTimer.interval = retrySecs * 1000;
        retrySecs = Math.min(retrySecs * 2, 120);
        retryTimer.restart();
    }

    // Send a frame. No-op while the socket is not open, which is what every
    // caller wants: the protocol layer resubscribes on `opened` anyway.
    function send(text) {
        socketLoader.item?.sendText(text);
    }

    Timer {
        id: retryTimer
        onTriggered: root.connect()
    }

    Timer {
        id: pingTimer
        interval: 30000
        repeat: true
        running: root.state === "connected"
        onTriggered: root.send(JSON.stringify({ _tag: "Ping" }))
    }

    Loader {
        id: socketLoader
        source: "T3Socket.qml"
        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("t3code: QtWebSockets unavailable — install qt6-qtwebsockets-devel");
                // Not a transport failure but the same symptom — a permanently
                // off chip — and the only one the user must act on. Nothing can
                // overwrite it: connect() returns on the not-Ready branch before
                // it ever requests a ticket, the Connections block below only
                // enables while the loader is Ready, and the one line that
                // clears connectionError runs on a socket that can never open.
                root.connectionError = "QtWebSockets is not installed";
                return;
            }
            // Pick up a connect() that arrived before this component finished
            // loading. retryTimer is stopped first: connect() armed it on the
            // not-ready path, and letting it fire afterwards would tear down
            // the socket this call is about to open.
            if (status === Loader.Ready && root.paired
                    && root.state !== "connected" && root.state !== "connecting") {
                retryTimer.stop();
                root.connect();
            }
        }
    }

    Connections {
        target: socketLoader.item
        enabled: socketLoader.status === Loader.Ready

        function onTextReceived(message) {
            root.message(message);
        }

        function onStatusChanged() {
            const st = socketLoader.item.status;
            if (st === 1) { // open
                // Cleared before the state change so no listener ever sees a
                // connected shell still carrying the failure it recovered from.
                root.connectionError = "";
                root.state = "connected";
                root.retrySecs = 5;
                root.opened();
            } else if (st === 3 || st === 4) { // closed | error
                // Qt raises the close and the error that caused it as two
                // separate transitions, in either order and with only one of
                // them carrying text (a refusal closes first, a TLS failure
                // errors first). So the reason is read on both, an empty
                // string never overwrites a real one, and the read sits
                // outside the guard below — by the time the error arrives the
                // close has often already scheduled the retry.
                const reason = Helpers.socketErrorText(socketLoader.item.errorString);
                if (reason !== "")
                    root.connectionError = reason;
                if (root.state === "connected" || root.state === "connecting")
                    root.scheduleRetry();
            }
        }
    }
}
