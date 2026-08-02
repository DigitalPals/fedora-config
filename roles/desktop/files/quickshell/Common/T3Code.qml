pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// T3 Code session monitor: keeps a live WebSocket subscription to the
// orchestration shell of the remote T3 Code server (t3.codes) and
// exposes project/thread state for the bar chip and popover.
//
// Auth model: `scripts/t3-pair.py <pairing-url>` exchanges a one-time
// pairing code for a ~30-day bearer token stored in
// ~/.local/state/t3code-bar.json. Each (re)connect trades that token
// for a 5-minute wsTicket via HTTP, then opens wss://…/ws?wsTicket=….
Singleton {
    id: root

    // "unpaired" | "connecting" | "connected" | "offline"
    property string state: "offline"
    property string host: ""            // https base url from the state file
    property string accessToken: ""
    property string environmentLabel: ""
    property string environmentId: ""

    // threadId → thread shell, projectId → project shell (raw server shapes)
    property var threadMap: ({})
    property var projectMap: ({})

    // Derived, popover-ready: sorted by urgency then recency.
    property var threads: []
    property int runningCount: 0
    property int attentionCount: 0
    property int doneCount: 0

    readonly property bool paired: host !== "" && accessToken !== ""
    readonly property string pairHint: "python3 ~/.config/quickshell/scripts/t3-pair.py '<pairing-url>'"

    // ---- classification ------------------------------------------------

    // "attention" | "running" | "error" | "done" | "idle"
    function threadClass(t) {
        if (t.hasPendingApprovals || t.hasPendingUserInput)
            return "attention";
        const sess = t.session ? t.session.status : "";
        const turn = t.latestTurn ? t.latestTurn.state : "";
        if (sess === "starting" || sess === "running" || turn === "running")
            return "running";
        const settled = t.settledOverride === "settled"
            || (t.settledAt !== null && t.settledOverride !== "active");
        if (sess === "error" || (turn === "error" && !settled))
            return "error";
        if (turn === "completed" && !settled)
            return "done";
        return "idle";
    }

    function projectTitle(projectId) {
        const p = projectMap[projectId];
        return p ? p.title : "";
    }

    function threadUrl(threadId) {
        if (host === "" || environmentId === "")
            return host;
        return host + "/" + environmentId + "/" + threadId;
    }

    function relTime(iso) {
        if (!iso)
            return "";
        let s = (Date.now() - Date.parse(iso)) / 1000;
        if (s < 90)
            return "now";
        if (s < 3600)
            return Math.round(s / 60) + "m";
        if (s < 86400)
            return Math.round(s / 3600) + "h";
        return Math.round(s / 86400) + "d";
    }

    function rebuild() {
        const rank = { attention: 0, error: 1, running: 2, done: 3, idle: 4 };
        let running = 0, attention = 0, done = 0;
        const list = [];
        for (const id in threadMap) {
            const t = threadMap[id];
            if (t.archivedAt)
                continue;
            const cls = threadClass(t);
            if (cls === "running")
                running++;
            else if (cls === "attention" || cls === "error")
                attention++;
            else if (cls === "done")
                done++;
            list.push({
                id: t.id,
                title: t.title,
                project: projectTitle(t.projectId),
                cls: cls,
                model: t.modelSelection ? t.modelSelection.model : "",
                updatedAt: t.updatedAt
            });
        }
        list.sort((a, b) => (rank[a.cls] - rank[b.cls])
            || (Date.parse(b.updatedAt) - Date.parse(a.updatedAt)));
        threads = list;
        runningCount = running;
        attentionCount = attention;
        doneCount = done;
    }

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
        }
    }

    // ---- connection ------------------------------------------------------

    property int retrySecs: 5
    property string wsRequestId: "1"

    function connect() {
        if (!paired || socketLoader.status !== Loader.Ready) {
            state = paired ? "offline" : "unpaired";
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
                }
            } else if (xhr.status === 401 || xhr.status === 403) {
                // Token expired or revoked: needs a fresh pairing URL.
                root.state = "unpaired";
                return;
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
        if (environmentId !== "")
            return;
        const xhr = new XMLHttpRequest();
        xhr.open("GET", host + "/.well-known/t3/environment");
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200)
                return;
            try {
                const d = JSON.parse(xhr.responseText);
                root.environmentId = d.environmentId ?? "";
                root.environmentLabel = d.label ?? "";
            } catch (e) {}
        };
        xhr.send();
    }

    function scheduleRetry() {
        if (socketLoader.item)
            socketLoader.item.active = false;
        if (state !== "unpaired")
            state = "offline";
        retryTimer.interval = retrySecs * 1000;
        retrySecs = Math.min(retrySecs * 2, 120);
        retryTimer.restart();
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
        onTriggered: socketLoader.item?.sendText(JSON.stringify({ _tag: "Ping" }))
    }

    // ---- protocol --------------------------------------------------------

    function subscribe() {
        threadMap = {};
        projectMap = {};
        rebuild();
        socketLoader.item.sendText(JSON.stringify({
            _tag: "Request",
            id: wsRequestId,
            tag: "orchestration.subscribeShell",
            payload: {},
            headers: []
        }));
    }

    function handleMessage(text) {
        let msgs;
        try {
            msgs = JSON.parse(text);
        } catch (e) {
            return;
        }
        if (!Array.isArray(msgs))
            msgs = [msgs];
        let dirty = false;
        for (const msg of msgs) {
            if (msg._tag === "Chunk") {
                socketLoader.item.sendText(JSON.stringify({ _tag: "Ack", requestId: msg.requestId }));
                for (const item of msg.values)
                    dirty = applyItem(item) || dirty;
            } else if (msg._tag === "Exit") {
                // Stream ended server-side (shutdown/restart): reconnect.
                scheduleRetry();
            }
        }
        if (dirty)
            rebuild();
    }

    function applyItem(item) {
        switch (item.kind) {
        case "snapshot": {
            const tm = {}, pm = {};
            for (const p of item.snapshot.projects)
                pm[p.id] = p;
            for (const t of item.snapshot.threads)
                tm[t.id] = t;
            projectMap = pm;
            threadMap = tm;
            return true;
        }
        case "project-upserted":
            projectMap[item.project.id] = item.project;
            return true;
        case "project-removed":
            delete projectMap[item.projectId];
            return true;
        case "thread-upserted":
            threadMap[item.thread.id] = item.thread;
            return true;
        case "thread-removed":
            delete threadMap[item.threadId];
            return true;
        default:
            return false;
        }
    }

    Loader {
        id: socketLoader
        source: "T3Socket.qml"
        onStatusChanged: {
            if (status === Loader.Error)
                console.warn("t3code: QtWebSockets unavailable — install qt6-qtwebsockets-devel");
        }
    }

    Connections {
        target: socketLoader.item
        enabled: socketLoader.status === Loader.Ready

        function onTextReceived(message) {
            root.handleMessage(message);
        }

        function onStatusChanged() {
            const st = socketLoader.item.status;
            if (st === 1) { // open
                root.state = "connected";
                root.retrySecs = 5;
                root.subscribe();
            } else if (st === 3 || st === 4) { // closed | error
                if (root.state === "connected" || root.state === "connecting")
                    root.scheduleRetry();
            }
        }
    }
}
