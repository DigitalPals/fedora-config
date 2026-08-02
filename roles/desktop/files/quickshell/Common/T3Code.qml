pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// T3 Code session monitor and remote control: keeps a live WebSocket
// subscription to the orchestration shell of the remote T3 Code server
// (t3.codes) and exposes project/thread state for the bar chip and
// popover, plus command dispatch (approvals, prompts, settle,
// interrupt) and desktop notifications on session transitions.
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

    // Expanded-thread detail (orchestration.subscribeThread).
    property string detailThreadId: ""
    property bool detailLoading: false
    property var detailApprovals: []

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

    // Previous class per thread, for transition notifications.
    property var lastClass: ({})

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
                pendingApprovals: t.hasPendingApprovals === true,
                pendingInput: t.hasPendingUserInput === true,
                updatedAt: t.updatedAt
            });
        }
        list.sort((a, b) => (rank[a.cls] - rank[b.cls])
            || (Date.parse(b.updatedAt) - Date.parse(a.updatedAt)));

        const next = {};
        for (const th of list) {
            next[th.id] = th.cls;
            const prev = lastClass[th.id];
            if (prev !== undefined && prev !== th.cls)
                notifyTransition(prev, th);
        }
        lastClass = next;

        threads = list;
        runningCount = running;
        attentionCount = attention;
        doneCount = done;
    }

    // A session asking for input is always worth a toast; finishing or
    // failing only when it was actually working a moment ago.
    function notifyTransition(prev, th) {
        let what;
        if (th.cls === "attention")
            what = th.pendingApprovals ? "waiting for approval" : "has a question";
        else if (th.cls === "error" && (prev === "running" || prev === "attention"))
            what = "failed";
        else if (th.cls === "done" && (prev === "running" || prev === "attention"))
            what = "finished";
        else
            return;
        Quickshell.execDetached(["notify-send", "-a", "T3 Code", "-i", "utilities-terminal",
            th.title, th.project + " · " + what]);
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

    readonly property string shellReqId: "1"
    property int nextReqId: 2
    // requestId → { item(value), exit(msg) } for non-shell streams.
    property var rpcHandlers: ({})

    function genId() {
        let s = "";
        for (let i = 0; i < 32; i++)
            s += Math.floor(Math.random() * 16).toString(16);
        return s;
    }

    function sendRequest(id, tag, payload) {
        socketLoader.item.sendText(JSON.stringify({
            _tag: "Request",
            id: id,
            tag: tag,
            payload: payload,
            headers: []
        }));
    }

    function subscribe() {
        rpcHandlers = {};
        nextReqId = 2;
        threadMap = {};
        projectMap = {};
        detailThreadId = "";
        detailApprovals = [];
        rebuild();
        sendRequest(shellReqId, "orchestration.subscribeShell", {});
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
            const reqId = msg.requestId !== undefined ? String(msg.requestId) : "";
            if (msg._tag === "Chunk") {
                socketLoader.item.sendText(JSON.stringify({ _tag: "Ack", requestId: msg.requestId }));
                if (reqId === shellReqId) {
                    for (const item of msg.values)
                        dirty = applyItem(item) || dirty;
                } else if (rpcHandlers[reqId]) {
                    for (const item of msg.values)
                        rpcHandlers[reqId].item?.(item);
                }
            } else if (msg._tag === "Exit") {
                if (reqId === shellReqId) {
                    // Stream ended server-side (shutdown/restart): reconnect.
                    scheduleRetry();
                } else if (rpcHandlers[reqId]) {
                    rpcHandlers[reqId].exit?.(msg);
                    delete rpcHandlers[reqId];
                }
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

    // ---- commands --------------------------------------------------------

    function dispatch(command) {
        if (state !== "connected")
            return;
        const id = String(nextReqId++);
        rpcHandlers[id] = {
            exit: msg => {
                if (msg.exit && msg.exit._tag === "Failure")
                    console.warn("t3code: command rejected:", JSON.stringify(msg.exit).slice(0, 300));
            }
        };
        sendRequest(id, "orchestration.dispatchCommand", command);
    }

    // decision: "accept" | "acceptForSession" | "decline"
    function respondApproval(threadId, requestId, decision) {
        dispatch({
            type: "thread.approval.respond",
            commandId: genId(),
            threadId: threadId,
            requestId: requestId,
            decision: decision,
            createdAt: new Date().toISOString()
        });
    }

    function settle(threadId) {
        dispatch({
            type: "thread.settle",
            commandId: genId(),
            threadId: threadId
        });
    }

    function interrupt(threadId) {
        dispatch({
            type: "thread.turn.interrupt",
            commandId: genId(),
            threadId: threadId,
            createdAt: new Date().toISOString()
        });
    }

    function startTurn(threadId, text) {
        const t = threadMap[threadId];
        if (!t || text.trim() === "")
            return;
        dispatch({
            type: "thread.turn.start",
            commandId: genId(),
            threadId: threadId,
            message: {
                messageId: genId(),
                role: "user",
                text: text,
                attachments: []
            },
            runtimeMode: t.runtimeMode ?? "full-access",
            interactionMode: t.interactionMode ?? "default",
            createdAt: new Date().toISOString()
        });
    }

    // ---- thread detail (pending approvals) --------------------------------

    property string detailReqId: ""
    property var detailActivities: []

    function openDetail(threadId) {
        closeDetail();
        if (state !== "connected")
            return;
        detailThreadId = threadId;
        detailLoading = true;
        detailActivities = [];
        detailApprovals = [];
        const id = String(nextReqId++);
        detailReqId = id;
        rpcHandlers[id] = {
            item: item => {
                if (item.kind === "snapshot") {
                    root.detailActivities = (item.snapshot.thread.activities ?? []).slice();
                    root.detailLoading = false;
                    root.recomputeApprovals();
                } else if (item.kind === "event" && item.event.type === "thread.activity-appended") {
                    root.detailActivities.push(item.event.payload.activity);
                    root.recomputeApprovals();
                }
            },
            exit: () => {
                if (root.detailReqId === id)
                    root.detailReqId = "";
            }
        };
        sendRequest(id, "orchestration.subscribeThread", { threadId: threadId });
    }

    function closeDetail() {
        if (detailReqId !== "") {
            socketLoader.item?.sendText(JSON.stringify({ _tag: "Interrupt", requestId: detailReqId }));
            delete rpcHandlers[detailReqId];
            detailReqId = "";
        }
        detailThreadId = "";
        detailLoading = false;
        detailActivities = [];
        detailApprovals = [];
    }

    // Mirrors the web client's derivePendingApprovals: open approval
    // requests are activity entries not yet matched by a resolution.
    function recomputeApprovals() {
        const open = {};
        for (const act of detailActivities) {
            const p = act.payload && typeof act.payload === "object" ? act.payload : {};
            const rid = typeof p.requestId === "string" ? p.requestId : null;
            if (!rid)
                continue;
            if (act.kind === "approval.requested") {
                open[rid] = {
                    requestId: rid,
                    kind: p.requestKind ?? approvalKind(p.requestType),
                    detail: typeof p.detail === "string" ? p.detail : "",
                    createdAt: act.createdAt
                };
            } else if (act.kind === "approval.resolved") {
                delete open[rid];
            } else if (act.kind === "provider.approval.respond.failed"
                       && /stale pending|unknown pending/i.test(p.detail ?? "")) {
                delete open[rid];
            }
        }
        detailApprovals = Object.values(open)
            .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
    }

    function approvalKind(requestType) {
        switch (requestType) {
        case "file_read_approval":
            return "file-read";
        case "file_change_approval":
        case "apply_patch_approval":
            return "file-change";
        default:
            return "command";
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
