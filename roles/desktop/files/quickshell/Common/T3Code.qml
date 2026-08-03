pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "T3CodeHelpers.js" as Helpers

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
    property string serverVersion: ""
    property var environmentCapabilities: ({})

    // Scope is persisted by t3-pair.py. Older state files do not contain it;
    // absence deliberately keeps the old "let the server authorize" behavior.
    property bool scopeMetadataKnown: false
    property var tokenScope: ""
    readonly property var scopeInfo: Helpers.normalizeScopes(tokenScope, scopeMetadataKnown)
    readonly property bool canRead: scopeInfo.canRead
    readonly property bool canOperate: scopeInfo.canOperate
    readonly property bool readOnly: scopeMetadataKnown && !canOperate
    readonly property bool canDispatch: canOperate && state === "connected"

    // Sanitized server.getConfig projection. Credentials, settings, paths,
    // scripts, and skills never enter this singleton.
    property bool configReady: false
    property bool configLoading: false
    property string configError: ""
    property var providerConfigurations: []
    readonly property bool hasReadyProvider: configReady
        && providerConfigurations.some(provider => provider.ready === true
            && Array.isArray(provider.models) && provider.models.length > 0)
    readonly property bool supportsSettlement:
        environmentCapabilities.threadSettlement === true
    readonly property bool supportsSnooze:
        environmentCapabilities.threadSnooze === true
    readonly property bool supportsTitleRegeneration:
        environmentCapabilities.threadTitleRegeneration === true

    // threadId → thread shell, projectId → project shell (raw server shapes)
    property var threadMap: ({})
    property var projectMap: ({})
    property bool shellReady: false
    readonly property bool hasProjects: Object.values(projectMap)
        .some(project => project && !project.deletedAt)

    // Derived, popover-ready: the active inbox only (settled and snoozed
    // threads are dropped), sorted by urgency then recency.
    property var threads: []
    property var snoozedThreads: []
    property var settledThreads: []
    property int runningCount: 0
    property int attentionCount: 0
    property int doneCount: 0
    property int settledCount: 0
    property int snoozedCount: 0

    // Expanded-thread detail (orchestration.subscribeThread). The popover
    // owns one selection, so there is deliberately only one detail stream.
    property string detailThreadId: ""
    property bool detailLoading: false
    property string detailError: ""
    property var detailMessages: []
    property var detailActivities: []
    property var detailProposedPlans: []
    property var detailCheckpoints: []
    property var detailSession: null
    property var detailLatestTurn: null
    property var detailApprovals: []
    property var detailPendingInputs: []
    property var detailLatestAssistant: null
    property var detailLatestActivity: null
    property var detailActionablePlan: null
    property var detailCheckpointSummary: null
    property var detailDiff: ({ checkpointRef: "", loading: false, error: "",
        text: "", fullText: "", truncated: false, totalChars: 0, totalLines: 0 })

    // Action state is keyed by kind/thread/request. Generic commands clear
    // when dispatch succeeds; approvals and structured input wait for the
    // provider's matching resolution activity.
    property var actionStates: ({})
    readonly property var detailActionStates: actionStates

    // Structured-input drafts live in the singleton rather than the Loader
    // delegate. A rejected response therefore survives closing the popover,
    // selecting another thread, and retrying. Only user-input.resolved removes
    // the matching draft.
    property var userInputDrafts: ({})
    property var userInputQuestionIndices: ({})
    property var handledRequestActivities: ({})

    // Composer state belongs to the process-wide singleton so Loader teardown,
    // navigation, and reconnects never discard text or selections.
    property var threadDrafts: ({})
    property var newThreadDraft: ({})
    property var pendingDraftMessages: ({})
    property string pendingNewThreadId: ""
    property string pendingNewThreadActionKey: ""

    signal newThreadConfirmed(string threadId)

    readonly property bool paired: host !== "" && accessToken !== ""
    readonly property string pairHint: "python3 ~/.config/quickshell/scripts/t3-pair.py '<pairing-url>'"

    // ---- classification ------------------------------------------------

    // Days of quiet after which a thread settles itself. Mirrors the web
    // client's sidebar setting (its default is 3); 0 disables auto-settle.
    property int autoSettleAfterDays: 3

    readonly property int dayMs: Helpers.DAY_MS
    // A turn.start is adopted by a session within seconds; past this the
    // message is a failed start, not pending work.
    readonly property int queuedTurnGraceMs: Helpers.QUEUED_TURN_GRACE_MS
    readonly property int actionTimeoutMs: 15000
    readonly property int maxPromptChars: Helpers.MAX_PROMPT_CHARS

    // Bumped once a minute so settledness and the relative time labels
    // follow the clock — both move without any server event.
    property double nowMs: Date.now()

    function parseMs(iso) {
        return Helpers.parseMs(iso);
    }

    // Newest real activity on a thread (reference: threadLastActivityAt).
    function lastActivityMs(t) {
        return Helpers.lastActivityMs(t);
    }

    // A user message no session has adopted yet: the turn exists but none
    // of the status fields show it, so it has to be detected as a message
    // strictly newer than every timestamp on the latest turn.
    function hasQueuedTurnStart(t, now) {
        return Helpers.hasQueuedTurnStart(t, now);
    }

    // Mirrors the reference client's effectiveSettled, which is what the
    // web sidebar partitions on: blocked or live work stays active whatever
    // the flags say, then an explicit settle/unsettle wins, then a thread
    // quiet past the window settles itself. The reference's third input —
    // pull request state — isn't subscribed here, so a merged PR only
    // settles its thread once the thread also goes quiet.
    function isSettled(t, now) {
        return Helpers.isEffectivelySettled(t, now, autoSettleAfterDays);
    }

    // Shelved until its wake time — unless the thread raises its hand:
    // blocked on the user, freshly failed, or finished a run after the
    // snooze was set.
    function isSnoozed(t, now) {
        return Helpers.isEffectivelySnoozed(t, now);
    }

    // "attention" | "running" | "error" | "done" | "idle". Only ever asked
    // of active threads — settledness is decided before this runs.
    function threadClass(t) {
        return Helpers.threadClass(t);
    }

    function threadCanPrompt(t, now) {
        return Helpers.canPrompt(t, now);
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

    // Reads nowMs so callers' bindings re-run on the minute tick.
    function relTime(iso) {
        if (!iso)
            return "";
        let s = (nowMs - Date.parse(iso)) / 1000;
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
    // Last published list, so a no-op rebuild leaves the popover's
    // delegates (and a half-typed prompt) alone.
    property string listSignature: ""

    function rebuild() {
        const now = Date.now();
        const projection = Helpers.classifyThreads(threadMap, projectMap, now,
            autoSettleAfterDays);
        const sig = JSON.stringify({
            active: projection.active,
            snoozed: projection.snoozed,
            settled: projection.settled
        });
        if (sig === listSignature)
            return;
        listSignature = sig;

        // Hidden threads keep a class of their own so one that comes back —
        // the server un-settles on a new approval or question — reads as a
        // transition and still raises its toast.
        const next = {};
        for (const th of projection.snoozed)
            next[th.id] = "hidden";
        for (const th of projection.settled)
            next[th.id] = "hidden";
        for (const th of projection.active) {
            next[th.id] = th.cls;
            const prev = lastClass[th.id];
            if (prev !== undefined && prev !== th.cls)
                notifyTransition(prev, th);
        }
        lastClass = next;

        threads = projection.active;
        snoozedThreads = projection.snoozed;
        settledThreads = projection.settled;
        runningCount = projection.runningCount;
        attentionCount = projection.attentionCount;
        doneCount = projection.doneCount;
        settledCount = projection.settled.length;
        snoozedCount = projection.snoozed.length;

        // Shell updates carry the freshest session/latest-turn summary even
        // while the detailed history stream is catching up.
        const selected = threadMap[detailThreadId];
        if (selected) {
            detailSession = selected.session ?? null;
            detailLatestTurn = selected.latestTurn ?? null;
            recomputeDetailDerived();
        }
    }

    function projectedThread(threadId) {
        for (const list of [threads, snoozedThreads, settledThreads]) {
            const found = list.find(thread => thread.id === threadId);
            if (found)
                return found;
        }
        return null;
    }

    function rawThread(threadId) {
        return threadMap[threadId] ?? null;
    }

    function sortedProjects() {
        return Object.values(projectMap).filter(project => project && !project.deletedAt)
            .sort((left, right) => (left.title ?? "").localeCompare(right.title ?? ""));
    }

    function snoozePresets() {
        return Helpers.resolveSnoozePresets(new Date());
    }

    function snoozeWakeLabel(iso) {
        return Helpers.snoozeWakeLabel(iso, nowMs);
    }

    function historyPage(messages, visibleCount) {
        return Helpers.historyPage(messages, visibleCount);
    }

    // Auto-settle and snooze wake are clock-driven: without a tick a thread
    // would sit in the list until the next server event.
    Timer {
        interval: 60000
        repeat: true
        running: root.state === "connected"
        onTriggered: {
            root.nowMs = Date.now();
            root.rebuild();
        }
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
            } catch (e) {}
        };
        xhr.send();
    }

    function scheduleRetry() {
        if (state === "connected")
            abortPendingRpcs();
        failAllPendingActions("Disconnected before confirmation");
        if (socketLoader.item)
            socketLoader.item.active = false;
        configLoading = false;
        configReady = false;
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
        if (!socketLoader.item || state !== "connected")
            return false;
        socketLoader.item.sendText(JSON.stringify({
            _tag: "Request",
            id: id,
            tag: tag,
            payload: payload,
            headers: []
        }));
        return true;
    }

    // Effect RPC sends zero or more Chunk values followed by one Exit. This
    // wrapper retains the final value, applies a hard timeout, and never
    // retries implicitly after a transport loss.
    function requestOnce(tag, payload, onSuccess, onFailure, options) {
        if (state !== "connected" || !socketLoader.item) {
            onFailure?.("Not connected");
            return "";
        }
        const id = String(nextReqId++);
        const opts = options ?? {};
        const handler = {
            value: undefined,
            deadline: Date.now() + (opts.timeoutMs ?? actionTimeoutMs),
            actionKey: opts.actionKey ?? "",
            item: value => { handler.value = value; },
            exit: msg => {
                if (msg.exit && msg.exit._tag === "Failure")
                    onFailure?.(root.failureMessage(msg, opts.fallback ?? "Request failed"));
                else {
                    // Unary Effect RPCs (including server.getConfig and the
                    // full-diff request) return their result on Success.value.
                    // Streams instead populate `handler.value` through Chunk.
                    const value = msg.exit && msg.exit.value !== undefined
                        ? msg.exit.value : handler.value;
                    onSuccess?.(value);
                }
            },
            timeout: () => onFailure?.("Request timed out"),
            disconnect: () => onFailure?.("Disconnected before confirmation")
        };
        rpcHandlers[id] = handler;
        if (!sendRequest(id, tag, payload)) {
            delete rpcHandlers[id];
            onFailure?.("Not connected");
            return "";
        }
        return id;
    }

    function abortPendingRpcs() {
        const handlers = rpcHandlers;
        rpcHandlers = {};
        for (const id in handlers)
            handlers[id].disconnect?.();
        detailReqId = "";
    }

    function loadServerConfig() {
        configLoading = true;
        configReady = false;
        configError = "";
        requestOnce("server.getConfig", {}, value => {
            if (!value || typeof value !== "object") {
                root.configLoading = false;
                root.configError = "Malformed server configuration";
                return;
            }
            const safe = Helpers.sanitizeServerConfig(value);
            root.providerConfigurations = safe.providers;
            root.environmentCapabilities = safe.capabilities;
            if (safe.environmentId !== "")
                root.environmentId = safe.environmentId;
            if (safe.label !== "")
                root.environmentLabel = safe.label;
            if (safe.serverVersion !== "")
                root.serverVersion = safe.serverVersion;
            root.configLoading = false;
            root.configReady = true;
            root.reconcileDraftSelections();
        }, error => {
            root.configLoading = false;
            root.configReady = false;
            root.configError = error;
        }, { fallback: "Server configuration unavailable" });
    }

    function subscribe() {
        const selected = detailThreadId;
        rpcHandlers = {};
        nextReqId = 2;
        threadMap = {};
        projectMap = {};
        shellReady = false;
        detailReqId = "";
        resetDetailData();
        nowMs = Date.now();
        rebuild();
        configReady = false;
        loadServerConfig();
        if (canRead)
            sendRequest(shellReqId, "orchestration.subscribeShell", {});
        else
            shellReady = false;
        // A reconnect invalidates every stream request id. Keep the user's
        // selection and establish a fresh detail stream on the new socket.
        if (selected !== "") {
            pendingDetailResubscribeId = selected;
            detailResubscribeTimer.restart();
        }
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
                    for (const item of (Array.isArray(msg.values) ? msg.values : []))
                        dirty = applyItem(item) || dirty;
                } else if (rpcHandlers[reqId]) {
                    for (const item of (Array.isArray(msg.values) ? msg.values : []))
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

    Timer {
        interval: 500
        repeat: true
        running: root.state === "connected"
        onTriggered: {
            const now = Date.now();
            for (const id in root.rpcHandlers) {
                const handler = root.rpcHandlers[id];
                if (handler.deadline === undefined || now < handler.deadline)
                    continue;
                socketLoader.item?.sendText(JSON.stringify({ _tag: "Interrupt", requestId: id }));
                delete root.rpcHandlers[id];
                handler.timeout?.();
            }
            const expired = Helpers.expireActionStates(root.actionStates, now,
                root.actionTimeoutMs);
            if (expired.expiredKeys.length > 0)
                root.actionStates = expired.states;
        }
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
            shellReady = true;
            reconcileDraftSelections();
            reconcileNewThreadCreation();
            return true;
        }
        case "synchronized":
            shellReady = true;
            return false;
        case "project-upserted": {
            const next = Object.assign({}, projectMap);
            next[item.project.id] = item.project;
            projectMap = next;
            return true;
        }
        case "project-removed": {
            const next = Object.assign({}, projectMap);
            delete next[item.projectId];
            projectMap = next;
            return true;
        }
        case "thread-upserted": {
            const next = Object.assign({}, threadMap);
            next[item.thread.id] = item.thread;
            threadMap = next;
            reconcileDraftSelections();
            reconcileNewThreadCreation(item.thread.id);
            return true;
        }
        case "thread-removed": {
            const next = Object.assign({}, threadMap);
            delete next[item.threadId];
            threadMap = next;
            return true;
        }
        default:
            return false;
        }
    }

    // ---- commands and action state ---------------------------------------

    function actionKey(kind, threadId, requestId) {
        return kind + "|" + threadId + "|" + (requestId ?? "");
    }

    function actionState(kind, threadId, requestId) {
        const states = actionStates;
        return states[actionKey(kind, threadId, requestId)] ?? null;
    }

    function actionPending(kind, threadId, requestId) {
        const current = actionState(kind, threadId, requestId);
        return current !== null && current.pending === true;
    }

    function actionError(kind, threadId, requestId) {
        const current = actionState(kind, threadId, requestId);
        return current && typeof current.error === "string" ? current.error : "";
    }

    function putActionState(key, value) {
        const next = Object.assign({}, actionStates);
        if (value === null)
            delete next[key];
        else
            next[key] = value;
        actionStates = next;
    }

    function beginAction(key, commandId, awaitResolution) {
        putActionState(key, {
            pending: true,
            error: "",
            commandId: commandId,
            awaitResolution: awaitResolution === true,
            startedAt: Date.now()
        });
    }

    function failAllPendingActions(message) {
        const next = Object.assign({}, actionStates);
        let changed = false;
        for (const key in next) {
            if (!next[key] || next[key].pending !== true)
                continue;
            next[key] = Object.assign({}, next[key], {
                pending: false,
                error: message || "Disconnected before confirmation"
            });
            changed = true;
        }
        if (changed)
            actionStates = next;
    }

    function failAction(key, message) {
        const current = actionStates[key];
        if (!current)
            return;
        putActionState(key, Object.assign({}, current, {
            pending: false,
            error: message || "Action failed"
        }));
    }

    function clearAction(key) {
        if (actionStates[key] !== undefined)
            putActionState(key, null);
    }

    function cancelActionRequests(key) {
        for (const id in rpcHandlers) {
            const handler = rpcHandlers[id];
            if (!handler || handler.actionKey !== key)
                continue;
            socketLoader.item?.sendText(JSON.stringify({ _tag: "Interrupt", requestId: id }));
            delete rpcHandlers[id];
        }
        clearAction(key);
    }

    function findErrorText(value, depth) {
        if (depth > 5 || value === null || value === undefined)
            return "";
        if (typeof value === "string")
            return value.trim();
        if (typeof value !== "object")
            return "";
        for (const key of ["message", "detail", "reason", "error", "cause", "failure"]) {
            if (value[key] !== undefined) {
                const found = findErrorText(value[key], depth + 1);
                if (found !== "" && found !== "Failure")
                    return found;
            }
        }
        return "";
    }

    function failureMessage(msg, fallback) {
        const found = findErrorText(msg ? msg.exit : null, 0);
        return found !== "" ? found.slice(0, 240) : fallback;
    }

    function rejectAction(key, message, awaitResolution) {
        putActionState(key, {
            pending: false,
            error: message,
            commandId: "",
            awaitResolution: awaitResolution === true,
            startedAt: Date.now()
        });
        return "";
    }

    // Dispatch commands one at a time. A later command is never attempted
    // after an earlier rejection, and reconnecting never replays the batch.
    function dispatchBatch(commands, key, options) {
        const opts = options ?? {};
        if (!Helpers.canBeginAction(actionStates, key))
            return "";
        if (!canOperate)
            return rejectAction(key, "This pairing is read-only", opts.awaitResolution);
        if (state !== "connected" || !socketLoader.item)
            return rejectAction(key, "Not connected", opts.awaitResolution);
        if (!Array.isArray(commands) || commands.length === 0)
            return rejectAction(key, "Nothing to send", opts.awaitResolution);

        const firstId = commands[0].commandId ?? genId();
        commands[0].commandId = firstId;
        beginAction(key, firstId, opts.awaitResolution);

        function sendAt(index) {
            if (!root.actionStates[key] || root.actionStates[key].pending !== true)
                return;
            if (index >= commands.length) {
                if (opts.awaitResolution !== true && opts.holdAfterSuccess !== true)
                    root.clearAction(key);
                opts.onSuccess?.();
                return;
            }
            const command = commands[index];
            if (!command.commandId)
                command.commandId = root.genId();
            const current = root.actionStates[key];
            root.putActionState(key, Object.assign({}, current, {
                commandId: command.commandId,
                startedAt: Date.now()
            }));
            requestOnce("orchestration.dispatchCommand", command, () => {
                sendAt(index + 1);
            }, error => {
                root.failAction(key, error || "Command rejected");
                opts.onFailure?.(error);
                console.warn("t3code: command rejected:", error);
            }, { actionKey: key, fallback: "Command rejected" });
        }

        sendAt(0);
        return firstId;
    }

    // Approval/input actions remain pending after RPC acceptance until the
    // provider's matching resolution activity arrives.
    function dispatch(command, key, awaitResolution) {
        return dispatchBatch([command], key, { awaitResolution: awaitResolution === true });
    }

    // decision: "accept" | "acceptForSession" | "decline"
    function respondApproval(threadId, requestId, decision) {
        const key = actionKey("approval", threadId, requestId);
        return dispatch({
            type: "thread.approval.respond",
            commandId: genId(),
            threadId: threadId,
            requestId: requestId,
            decision: decision,
            createdAt: new Date().toISOString()
        }, key, true);
    }

    // Answers are deliberately narrowed to the two provider contract shapes
    // the dropdown can author: a string or an array of strings.
    function respondUserInput(threadId, requestId, answers) {
        const key = actionKey("input", threadId, requestId);
        const normalized = {};
        let answerCount = 0;
        if (!answers || typeof answers !== "object" || Array.isArray(answers)) {
            putActionState(key, { pending: false, error: "Every question needs an answer",
                commandId: "", awaitResolution: true, startedAt: Date.now() });
            return "";
        }
        for (const questionId in answers) {
            const value = answers[questionId];
            if (typeof value === "string") {
                const answer = value.trim();
                if (answer === "")
                    continue;
                normalized[questionId] = answer;
                answerCount++;
            } else if (Array.isArray(value)) {
                const labels = value.filter(label => typeof label === "string")
                    .map(label => label.trim()).filter(label => label !== "");
                if (labels.length === 0)
                    continue;
                normalized[questionId] = Array.from(new Set(labels));
                answerCount++;
            } else {
                putActionState(key, { pending: false, error: "Unsupported answer format",
                    commandId: "", awaitResolution: true, startedAt: Date.now() });
                return "";
            }
        }
        if (answerCount === 0) {
            putActionState(key, { pending: false, error: "Every question needs an answer",
                commandId: "", awaitResolution: true, startedAt: Date.now() });
            return "";
        }
        return dispatch({
            type: "thread.user-input.respond",
            commandId: genId(),
            threadId: threadId,
            requestId: requestId,
            answers: normalized,
            createdAt: new Date().toISOString()
        }, key, true);
    }

    function settle(threadId) {
        const key = actionKey("settle", threadId, "");
        const thread = threadMap[threadId];
        if (!supportsSettlement)
            return rejectAction(key, "Settlement is not supported by this server", false);
        if (!Helpers.canOperateLifecycle(thread, Date.now()))
            return rejectAction(key, "Wait for the thread to become idle", false);
        return dispatch({
            type: "thread.settle",
            commandId: genId(),
            threadId: threadId
        }, key, false);
    }

    function unsettle(threadId) {
        const key = actionKey("unsettle", threadId, "");
        if (!supportsSettlement)
            return rejectAction(key, "Settlement is not supported by this server", false);
        return dispatch({
            type: "thread.unsettle",
            commandId: genId(),
            threadId: threadId,
            reason: "user"
        }, key, false);
    }

    function settleMany(threadIds) {
        const key = actionKey("bulk-settle", "", "");
        if (!supportsSettlement)
            return rejectAction(key, "Settlement is not supported by this server", false);
        const ids = Array.isArray(threadIds) ? threadIds.filter(id =>
            Helpers.canOperateLifecycle(threadMap[id], Date.now())) : [];
        const commands = ids.map(id => ({
            type: "thread.settle", commandId: genId(), threadId: id
        }));
        return dispatchBatch(commands, key, {});
    }

    function snooze(threadId, snoozedUntil) {
        const key = actionKey("snooze", threadId, "");
        const thread = threadMap[threadId];
        if (!supportsSnooze)
            return rejectAction(key, "Snooze is not supported by this server", false);
        if (!Helpers.canOperateLifecycle(thread, Date.now()))
            return rejectAction(key, "Wait for the thread to become idle", false);
        if (isNaN(Date.parse(snoozedUntil)) || Date.parse(snoozedUntil) <= Date.now())
            return rejectAction(key, "Choose a future wake time", false);
        return dispatch({
            type: "thread.snooze",
            commandId: genId(),
            threadId: threadId,
            snoozedUntil: snoozedUntil
        }, key, false);
    }

    function unsnooze(threadId) {
        const key = actionKey("unsnooze", threadId, "");
        if (!supportsSnooze)
            return rejectAction(key, "Snooze is not supported by this server", false);
        return dispatch({
            type: "thread.unsnooze",
            commandId: genId(),
            threadId: threadId,
            reason: "user"
        }, key, false);
    }

    function interrupt(threadId) {
        return dispatch({
            type: "thread.turn.interrupt",
            commandId: genId(),
            threadId: threadId,
            createdAt: new Date().toISOString()
        }, actionKey("interrupt", threadId, ""), false);
    }

    function stopSession(threadId) {
        return dispatch({
            type: "thread.session.stop",
            commandId: genId(),
            threadId: threadId,
            createdAt: new Date().toISOString()
        }, actionKey("session-stop", threadId, ""), false);
    }

    function renameThread(threadId, title) {
        const key = actionKey("rename", threadId, "");
        const normalized = typeof title === "string" ? title.trim() : "";
        if (normalized === "")
            return rejectAction(key, "Title cannot be empty", false);
        return dispatch({
            type: "thread.meta.update",
            commandId: genId(),
            threadId: threadId,
            title: normalized
        }, key, false);
    }

    function regenerateTitle(threadId) {
        const key = actionKey("regenerate-title", threadId, "");
        if (!supportsTitleRegeneration)
            return rejectAction(key, "Title regeneration is not supported", false);
        if (threadMap[threadId]?.titleRegeneration)
            return rejectAction(key, "Title regeneration is already running", false);
        return dispatch({
            type: "thread.meta.update",
            commandId: genId(),
            threadId: threadId,
            regenerateTitle: true
        }, key, false);
    }

    // ---- composer drafts and provider selection --------------------------

    function providerConfiguration(instanceId) {
        return Helpers.findProvider(providerConfigurations, instanceId);
    }

    function modelConfiguration(instanceId, model) {
        return Helpers.findModel(providerConfiguration(instanceId), model);
    }

    function canonicalOptions(raw) {
        if (Array.isArray(raw))
            return raw.filter(option => option && typeof option.id === "string"
                && (typeof option.value === "string" || typeof option.value === "boolean"))
                .map(option => ({ id: option.id, value: option.value }));
        const result = [];
        if (raw && typeof raw === "object") {
            for (const id in raw) {
                if (typeof raw[id] === "string" || typeof raw[id] === "boolean")
                    result.push({ id: id, value: raw[id] });
            }
        }
        return result;
    }

    function normalizedOptions(instanceId, model, raw) {
        const config = modelConfiguration(instanceId, model);
        if (!config)
            return canonicalOptions(raw);
        return Helpers.traitSelections(Helpers.normalizeTraits(config.optionDescriptors, raw));
    }

    function selectionFromDraft(draft) {
        if (!draft)
            return null;
        const provider = providerConfiguration(draft.instanceId);
        const model = Helpers.findModel(provider, draft.model);
        if (!provider || provider.ready !== true || !model)
            return null;
        return {
            instanceId: provider.instanceId,
            model: model.slug,
            options: normalizedOptions(provider.instanceId, model.slug, draft.options)
        };
    }

    function reconcileDraftSelections() {
        let draftsChanged = false;
        const drafts = Object.assign({}, threadDrafts);
        for (const threadId in drafts) {
            const draft = drafts[threadId];
            let selection = selectionFromDraft(draft);
            if (!selection)
                selection = Helpers.selectionForThread(threadMap[threadId], providerConfigurations);
            if (!selection)
                continue;
            const current = {
                instanceId: draft.instanceId ?? "",
                model: draft.model ?? "",
                options: canonicalOptions(draft.options)
            };
            if (!Helpers.sameSelection(current, selection)) {
                drafts[threadId] = Object.assign({}, draft, {
                    instanceId: selection.instanceId,
                    model: selection.model,
                    options: selection.options ?? [],
                    traitError: ""
                });
                draftsChanged = true;
            }
        }
        if (draftsChanged)
            threadDrafts = drafts;

        if (newThreadDraft && typeof newThreadDraft.projectId === "string"
                && newThreadDraft.projectId !== "") {
            let newSelection = selectionFromDraft(newThreadDraft);
            if (!newSelection)
                newSelection = Helpers.selectionForProject(
                    projectMap[newThreadDraft.projectId], providerConfigurations);
            if (newSelection) {
                const currentNew = {
                    instanceId: newThreadDraft.instanceId ?? "",
                    model: newThreadDraft.model ?? "",
                    options: canonicalOptions(newThreadDraft.options)
                };
                if (!Helpers.sameSelection(currentNew, newSelection)) {
                    newThreadDraft = Object.assign({}, newThreadDraft, {
                        instanceId: newSelection.instanceId,
                        model: newSelection.model,
                        options: newSelection.options ?? [],
                        traitError: ""
                    });
                }
            }
        }
    }

    function makeThreadDraft(thread) {
        const persisted = thread && thread.modelSelection ? thread.modelSelection : {};
        const resolved = Helpers.selectionForThread(thread, providerConfigurations);
        const selection = resolved ?? persisted;
        return {
            prompt: "",
            instanceId: selection.instanceId ?? thread?.session?.providerInstanceId ?? "",
            model: selection.model ?? "",
            options: normalizedOptions(selection.instanceId ?? "", selection.model ?? "",
                selection.options),
            runtimeMode: thread?.runtimeMode ?? "full-access",
            interactionMode: thread?.interactionMode ?? "default",
            traitError: ""
        };
    }

    function ensureThreadDraft(threadId) {
        if (threadDrafts[threadId] !== undefined)
            return threadDrafts[threadId];
        const thread = threadMap[threadId];
        if (!thread)
            return null;
        const next = Object.assign({}, threadDrafts);
        next[threadId] = makeThreadDraft(thread);
        threadDrafts = next;
        return next[threadId];
    }

    function threadDraft(threadId) {
        return threadDrafts[threadId] ?? ({ prompt: "", instanceId: "", model: "",
            options: [], runtimeMode: "full-access", interactionMode: "default",
            traitError: "" });
    }

    function updateThreadDraft(threadId, fields) {
        const current = ensureThreadDraft(threadId);
        if (!current)
            return;
        const drafts = Object.assign({}, threadDrafts);
        drafts[threadId] = Object.assign({}, current, fields);
        threadDrafts = drafts;
    }

    function setThreadPrompt(threadId, prompt) {
        updateThreadDraft(threadId, { prompt: typeof prompt === "string" ? prompt : "" });
    }

    function setThreadProvider(threadId, instanceId) {
        const thread = threadMap[threadId];
        const allowed = Helpers.selectableProvidersForThread(thread, providerConfigurations,
            detailThreadId === threadId ? detailMessages.length : 0);
        const provider = Helpers.findProvider(allowed, instanceId);
        if (!provider)
            return;
        const model = Helpers.defaultModel(provider);
        if (!Helpers.modelChangeAllowed(thread, { instanceId: instanceId, model: model },
                providerConfigurations, detailThreadId === threadId ? detailMessages.length : 0)) {
            updateThreadDraft(threadId, {
                traitError: "This provider requires a new thread to change models"
            });
            return;
        }
        const modelConfig = Helpers.findModel(provider, model);
        updateThreadDraft(threadId, {
            instanceId: provider.instanceId,
            model: model,
            options: normalizedOptions(provider.instanceId, model,
                modelConfig ? null : []),
            traitError: ""
        });
    }

    function setThreadModel(threadId, model) {
        const thread = threadMap[threadId];
        const draft = threadDraft(threadId);
        const provider = providerConfiguration(draft.instanceId);
        const config = Helpers.findModel(provider, model);
        if (!config)
            return;
        const nextSelection = { instanceId: draft.instanceId, model: model };
        if (!Helpers.modelChangeAllowed(thread, nextSelection, providerConfigurations,
                detailThreadId === threadId ? detailMessages.length : 0)) {
            updateThreadDraft(threadId, {
                traitError: "This provider requires a new thread to change models"
            });
            return;
        }
        updateThreadDraft(threadId, {
            model: model,
            options: normalizedOptions(draft.instanceId, model, null),
            traitError: ""
        });
    }

    function setThreadRuntime(threadId, runtimeMode) {
        updateThreadDraft(threadId, { runtimeMode: runtimeMode });
    }

    function setThreadInteraction(threadId, interactionMode) {
        updateThreadDraft(threadId, { interactionMode: interactionMode });
    }

    function threadProviderChoices(threadId) {
        const thread = threadMap[threadId];
        const detailCount = detailThreadId === threadId ? detailMessages.length : 0;
        const currentInstanceId = thread?.session?.providerInstanceId
            ?? thread?.modelSelection?.instanceId ?? "";
        return Helpers.selectableProvidersForThread(thread, providerConfigurations, detailCount)
            .filter(provider => provider.instanceId === currentInstanceId
                || Helpers.modelChangeAllowed(thread, {
                    instanceId: provider.instanceId,
                    model: Helpers.defaultModel(provider)
                }, providerConfigurations, detailCount));
    }

    function threadModelChoices(threadId) {
        const draft = threadDraft(threadId);
        const provider = providerConfiguration(draft.instanceId);
        if (!provider)
            return [];
        return provider.models.filter(model => Helpers.modelChangeAllowed(threadMap[threadId],
            { instanceId: provider.instanceId, model: model.slug }, providerConfigurations,
            detailThreadId === threadId ? detailMessages.length : 0));
    }

    function draftTraitDescriptors(draft) {
        const model = draft ? modelConfiguration(draft.instanceId, draft.model) : null;
        return Helpers.traitsForPrompt(model ? model.optionDescriptors : [],
            draft ? draft.options : [], draft ? draft.prompt : "");
    }

    function updateThreadTrait(threadId, descriptorId, value) {
        const draft = threadDraft(threadId);
        const result = Helpers.applyTraitValue(draftTraitDescriptors(draft), descriptorId,
            value, draft.prompt);
        updateThreadDraft(threadId, { options: result.selections, prompt: result.prompt,
            traitError: result.error });
    }

    function defaultProjectId(contextThreadId) {
        const context = threadMap[contextThreadId];
        if (context && projectMap[context.projectId])
            return context.projectId;
        const projects = sortedProjects();
        return projects.length > 0 ? projects[0].id : "";
    }

    function buildNewDraft(projectId, prompt, sourceProposedPlan, projectFixed, modeFixed) {
        const project = projectMap[projectId];
        const selection = Helpers.selectionForProject(project, providerConfigurations);
        return {
            projectId: projectId,
            projectFixed: projectFixed === true,
            modeFixed: modeFixed === true,
            prompt: typeof prompt === "string" ? prompt : "",
            instanceId: selection ? selection.instanceId : "",
            model: selection ? selection.model : "",
            options: selection && Array.isArray(selection.options) ? selection.options : [],
            runtimeMode: "full-access",
            interactionMode: "default",
            sourceProposedPlan: sourceProposedPlan ?? null,
            traitError: ""
        };
    }

    function ensureNewThreadDraft(contextThreadId) {
        if (newThreadDraft && typeof newThreadDraft.projectId === "string"
                && newThreadDraft.projectId !== "")
            return newThreadDraft;
        const projectId = defaultProjectId(contextThreadId);
        newThreadDraft = buildNewDraft(projectId, "", null, false, false);
        return newThreadDraft;
    }

    function updateNewThreadDraft(fields) {
        newThreadDraft = Object.assign({}, newThreadDraft, fields);
    }

    function setNewPrompt(prompt) {
        updateNewThreadDraft({ prompt: typeof prompt === "string" ? prompt : "" });
    }

    function setNewProject(projectId) {
        if (newThreadDraft.projectFixed === true || !projectMap[projectId])
            return;
        const replacement = buildNewDraft(projectId, newThreadDraft.prompt, null, false, false);
        newThreadDraft = replacement;
    }

    function setNewProvider(instanceId) {
        const provider = Helpers.findProvider(providerConfigurations, instanceId);
        if (!provider || provider.ready !== true)
            return;
        const model = Helpers.defaultModel(provider);
        updateNewThreadDraft({ instanceId: instanceId, model: model,
            options: normalizedOptions(instanceId, model, null), traitError: "" });
    }

    function setNewModel(model) {
        const provider = providerConfiguration(newThreadDraft.instanceId);
        if (!Helpers.findModel(provider, model))
            return;
        updateNewThreadDraft({ model: model,
            options: normalizedOptions(newThreadDraft.instanceId, model, null),
            traitError: "" });
    }

    function setNewRuntime(runtimeMode) {
        updateNewThreadDraft({ runtimeMode: runtimeMode });
    }

    function setNewInteraction(interactionMode) {
        if (newThreadDraft.modeFixed !== true)
            updateNewThreadDraft({ interactionMode: interactionMode });
    }

    function updateNewTrait(descriptorId, value) {
        const result = Helpers.applyTraitValue(draftTraitDescriptors(newThreadDraft),
            descriptorId, value, newThreadDraft.prompt);
        updateNewThreadDraft({ options: result.selections, prompt: result.prompt,
            traitError: result.error });
    }

    function newProviderChoices() {
        return providerConfigurations.filter(provider => provider.ready === true
            && provider.models.length > 0);
    }

    function newModelChoices() {
        const provider = providerConfiguration(newThreadDraft.instanceId);
        return provider ? provider.models : [];
    }

    function providerShowsInteraction(instanceId) {
        const provider = providerConfiguration(instanceId);
        return provider ? provider.showInteractionModeToggle !== false : true;
    }

    function prepareNewThreadForPlan(sourceThreadId, plan) {
        const source = threadMap[sourceThreadId];
        if (!source || !plan)
            return false;
        newThreadDraft = buildNewDraft(source.projectId,
            Helpers.buildPlanImplementationPrompt(plan.planMarkdown),
            { threadId: sourceThreadId, planId: plan.id }, true, true);
        return true;
    }

    function putPendingDraftMessage(threadId, value) {
        const next = Object.assign({}, pendingDraftMessages);
        if (value === null)
            delete next[threadId];
        else
            next[threadId] = value;
        pendingDraftMessages = next;
    }

    function confirmDraftMessage(threadId, messageId) {
        const pending = pendingDraftMessages[threadId];
        if (!pending || pending.messageId !== messageId)
            return;
        if (pending.clearDraft === true) {
            const current = threadDraft(threadId);
            if (current.prompt === pending.prompt)
                updateThreadDraft(threadId, Helpers.draftAfterOutcome(current, "confirmed"));
        }
        putPendingDraftMessage(threadId, null);
    }

    function submitExisting(threadId, overrideText, interactionOverride, sourceProposedPlan,
            clearDraft) {
        const thread = threadMap[threadId];
        const draft = threadDraft(threadId);
        const key = actionKey("prompt", threadId, "");
        const text = typeof overrideText === "string" ? overrideText : draft.prompt;
        if (!thread || text.trim() === "")
            return rejectAction(key, "Write a message first", false);
        if (text.length > maxPromptChars)
            return rejectAction(key, "Prompt exceeds T3 Code's 120,000 character limit", false);
        if (!Helpers.canOperateLifecycle(thread, Date.now()))
            return rejectAction(key, "Wait for the thread to become idle", false);
        const interactionMode = interactionOverride ?? draft.interactionMode;
        if (!sourceProposedPlan && thread.hasActionableProposedPlan === true
                && interactionMode !== "plan")
            return rejectAction(key, "Choose a plan action before continuing", false);
        const selection = selectionFromDraft(draft);
        if (!selection)
            return rejectAction(key, "Choose a ready provider and model", false);
        if (!Helpers.modelChangeAllowed(thread, selection, providerConfigurations,
                detailThreadId === threadId ? detailMessages.length : 0))
            return rejectAction(key, "Start a new thread to change this model", false);
        const createdAt = new Date().toISOString();
        const messageId = genId();
        const commands = Helpers.buildExistingTurnCommands({
            currentThread: thread,
            modelSelection: selection,
            runtimeMode: draft.runtimeMode,
            interactionMode: interactionMode,
            text: text,
            messageId: messageId,
            sourceProposedPlan: sourceProposedPlan ?? null,
            createdAt: createdAt,
            nextId: () => root.genId()
        });
        putPendingDraftMessage(threadId, { messageId: messageId, prompt: text,
            clearDraft: clearDraft !== false });
        return dispatchBatch(commands, key, {
            // RPC acceptance is not the same as seeing the persisted message.
            // Keep the draft until the detail event (or a reconnect snapshot)
            // confirms this exact message id.
            onSuccess: () => {},
            onFailure: () => { /* draft and correlation stay for reconnect reconciliation */ }
        });
    }

    function startTurn(threadId, text) {
        setThreadPrompt(threadId, text);
        return submitExisting(threadId, undefined, undefined, null, true);
    }

    function implementPlanHere(threadId, plan) {
        if (!plan)
            return "";
        updateThreadDraft(threadId, { interactionMode: "default" });
        return submitExisting(threadId, Helpers.buildPlanImplementationPrompt(plan.planMarkdown),
            "default", { threadId: threadId, planId: plan.id }, false);
    }

    function refinePlan(threadId) {
        updateThreadDraft(threadId, { interactionMode: "plan" });
    }

    function submitNewThread() {
        const draft = newThreadDraft;
        const key = actionKey("new", "", "");
        const text = draft && typeof draft.prompt === "string" ? draft.prompt : "";
        if (!hasReadyProvider)
            return rejectAction(key, configReady ? "No provider with an advertised model is ready"
                : "Provider configuration is not ready", false);
        if (!draft || !projectMap[draft.projectId])
            return rejectAction(key, "Choose a project", false);
        if (text.trim() === "")
            return rejectAction(key, "Write the first prompt", false);
        if (text.length > maxPromptChars)
            return rejectAction(key, "Prompt exceeds T3 Code's 120,000 character limit", false);
        const selection = selectionFromDraft(draft);
        if (!selection)
            return rejectAction(key, "Choose a ready provider and model", false);
        const threadId = genId();
        const createdAt = new Date().toISOString();
        const command = Helpers.buildNewThreadCommand({
            threadId: threadId,
            projectId: draft.projectId,
            text: text,
            modelSelection: selection,
            runtimeMode: draft.runtimeMode,
            interactionMode: draft.modeFixed === true ? "default" : draft.interactionMode,
            sourceProposedPlan: draft.sourceProposedPlan,
            messageId: genId(),
            createdAt: createdAt,
            nextId: () => root.genId()
        });
        pendingNewThreadId = threadId;
        pendingNewThreadActionKey = key;
        const dispatched = dispatchBatch([command], key, {
            holdAfterSuccess: true,
            onSuccess: () => {
                const current = root.actionStates[key];
                if (current)
                    root.putActionState(key, Object.assign({}, current, {
                        pending: true, startedAt: Date.now(), phase: "awaiting-shell"
                    }));
            }
        });
        if (dispatched === "") {
            pendingNewThreadId = "";
            pendingNewThreadActionKey = "";
        }
        return dispatched;
    }

    function reconcileNewThreadCreation(candidateId) {
        if (pendingNewThreadId === "")
            return;
        if (candidateId !== undefined && candidateId !== pendingNewThreadId)
            return;
        if (!threadMap[pendingNewThreadId])
            return;
        const confirmed = pendingNewThreadId;
        if (pendingNewThreadActionKey !== "")
            clearAction(pendingNewThreadActionKey);
        pendingNewThreadId = "";
        pendingNewThreadActionKey = "";
        newThreadDraft = ({});
        newThreadConfirmed(confirmed);
    }

    // ---- structured-input drafts ----------------------------------------

    function inputRequestKey(threadId, requestId) {
        return threadId + "|" + requestId;
    }

    function inputDraftKey(threadId, requestId, questionId) {
        return inputRequestKey(threadId, requestId) + "|" + questionId;
    }

    function inputDraft(threadId, requestId, questionId) {
        return userInputDrafts[inputDraftKey(threadId, requestId, questionId)] ?? {
            selected: [], custom: ""
        };
    }

    function inputSelectedLabels(threadId, requestId, questionId) {
        const selected = inputDraft(threadId, requestId, questionId).selected;
        return Array.isArray(selected) ? selected : [];
    }

    function inputCustomAnswer(threadId, requestId, questionId) {
        const custom = inputDraft(threadId, requestId, questionId).custom;
        return typeof custom === "string" ? custom : "";
    }

    function toggleInputOption(threadId, requestId, questionId, label, multiSelect) {
        if (typeof label !== "string" || label.trim() === "")
            return;
        const key = inputDraftKey(threadId, requestId, questionId);
        const current = inputDraft(threadId, requestId, questionId);
        let selected = Array.isArray(current.selected) ? current.selected.slice() : [];
        if (multiSelect === true) {
            const at = selected.indexOf(label);
            if (at >= 0)
                selected.splice(at, 1);
            else
                selected.push(label);
        } else {
            selected = [label];
        }
        const next = Object.assign({}, userInputDrafts);
        next[key] = { selected: selected, custom: "" };
        userInputDrafts = next;
    }

    function setInputCustomAnswer(threadId, requestId, questionId, value) {
        const key = inputDraftKey(threadId, requestId, questionId);
        const current = inputDraft(threadId, requestId, questionId);
        const custom = typeof value === "string" ? value : "";
        const next = Object.assign({}, userInputDrafts);
        next[key] = {
            selected: custom.trim() !== "" ? []
                : (Array.isArray(current.selected) ? current.selected : []),
            custom: custom
        };
        userInputDrafts = next;
    }

    function inputQuestionIndex(threadId, requestId) {
        const value = userInputQuestionIndices[inputRequestKey(threadId, requestId)];
        return typeof value === "number" && isFinite(value) ? Math.max(0, Math.floor(value)) : 0;
    }

    function setInputQuestionIndex(threadId, requestId, value) {
        const next = Object.assign({}, userInputQuestionIndices);
        next[inputRequestKey(threadId, requestId)] = Math.max(0, Math.floor(value));
        userInputQuestionIndices = next;
    }

    function resolvedInputAnswer(threadId, requestId, question) {
        if (!question || typeof question.id !== "string")
            return null;
        const draft = inputDraft(threadId, requestId, question.id);
        const custom = typeof draft.custom === "string" ? draft.custom.trim() : "";
        if (custom !== "")
            return custom;
        const selected = Array.isArray(draft.selected)
            ? draft.selected.filter(label => typeof label === "string" && label.trim() !== "") : [];
        if (question.multiSelect === true)
            return selected.length > 0 ? selected : null;
        return selected.length > 0 ? selected[0] : null;
    }

    function inputQuestionAnswered(threadId, requestId, question) {
        return resolvedInputAnswer(threadId, requestId, question) !== null;
    }

    function buildInputAnswers(threadId, pendingInput) {
        if (!pendingInput || !Array.isArray(pendingInput.questions)
                || pendingInput.questions.length === 0)
            return null;
        const answers = {};
        for (const question of pendingInput.questions) {
            const answer = resolvedInputAnswer(threadId, pendingInput.requestId, question);
            if (answer === null)
                return null;
            answers[question.id] = answer;
        }
        return answers;
    }

    function clearUserInputDraft(threadId, requestId) {
        const requestKey = inputRequestKey(threadId, requestId);
        const prefix = requestKey + "|";
        const drafts = Object.assign({}, userInputDrafts);
        let changed = false;
        for (const key in drafts) {
            if (key.indexOf(prefix) === 0) {
                delete drafts[key];
                changed = true;
            }
        }
        if (changed)
            userInputDrafts = drafts;
        if (userInputQuestionIndices[requestKey] !== undefined) {
            const indices = Object.assign({}, userInputQuestionIndices);
            delete indices[requestKey];
            userInputQuestionIndices = indices;
        }
    }

    // ---- selected thread detail -----------------------------------------

    property string detailReqId: ""
    property string pendingDetailResubscribeId: ""

    function resetDetailData() {
        detailLoading = false;
        detailError = "";
        detailMessages = [];
        detailActivities = [];
        detailProposedPlans = [];
        detailCheckpoints = [];
        detailSession = null;
        detailLatestTurn = null;
        detailApprovals = [];
        detailPendingInputs = [];
        detailLatestAssistant = null;
        detailLatestActivity = null;
        detailActionablePlan = null;
        detailCheckpointSummary = null;
        detailDiff = ({ checkpointRef: "", loading: false, error: "", text: "", fullText: "",
            truncated: false, totalChars: 0, totalLines: 0 });
    }

    function historyCompare(left, right) {
        if (typeof left?.sequence === "number" && typeof right?.sequence === "number"
                && left.sequence !== right.sequence)
            return left.sequence - right.sequence;
        const lm = parseMs(left?.createdAt ?? left?.updatedAt ?? left?.completedAt);
        const rm = parseMs(right?.createdAt ?? right?.updatedAt ?? right?.completedAt);
        if (!isNaN(lm) && !isNaN(rm) && lm !== rm)
            return lm - rm;
        const lid = typeof left?.id === "string" ? left.id : "";
        const rid = typeof right?.id === "string" ? right.id : "";
        return lid.localeCompare(rid);
    }

    function sortedHistory(values) {
        return (Array.isArray(values) ? values.slice() : []).sort(historyCompare);
    }

    function upsertHistory(values, value, idField) {
        const next = Array.isArray(values) ? values.slice() : [];
        const key = value ? value[idField] : undefined;
        let at = -1;
        if (key !== undefined && key !== null)
            at = next.findIndex(entry => entry && entry[idField] === key);
        if (at >= 0)
            next[at] = value;
        else if (value)
            next.push(value);
        return sortedHistory(next);
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

    function stalePendingFailure(detail) {
        return /stale pending (approval|user[- ]input) request|unknown pending (approval|permission|user[- ]input|codex user input) request/i
            .test(typeof detail === "string" ? detail : "");
    }

    function parseInputQuestions(payload) {
        if (!payload || !Array.isArray(payload.questions))
            return null;
        const questions = [];
        for (const raw of payload.questions) {
            if (!raw || typeof raw !== "object" || typeof raw.id !== "string"
                    || typeof raw.question !== "string" || !Array.isArray(raw.options))
                continue;
            const options = [];
            for (const rawOption of raw.options) {
                if (!rawOption || typeof rawOption !== "object"
                        || typeof rawOption.label !== "string")
                    continue;
                const label = rawOption.label.trim();
                if (label === "")
                    continue;
                options.push({
                    label: label,
                    description: typeof rawOption.description === "string"
                        ? rawOption.description : ""
                });
            }
            if (raw.id.trim() === "" || raw.question.trim() === "" || options.length === 0)
                continue;
            questions.push({
                id: raw.id,
                header: typeof raw.header === "string" && raw.header.trim() !== ""
                    ? raw.header : "Question",
                question: raw.question,
                options: options,
                multiSelect: raw.multiSelect === true
            });
        }
        return questions.length > 0 ? questions : null;
    }

    function requestActivityId(activity) {
        if (activity && typeof activity.id === "string" && activity.id !== "")
            return activity.id;
        const payload = activity && typeof activity.payload === "object" ? activity.payload : {};
        return (activity?.kind ?? "") + "|" + (payload.requestId ?? "") + "|"
            + (activity?.createdAt ?? "");
    }

    function reconcileRequestActivity(activity, threadId) {
        if (!activity)
            return;
        const terminal = activity.kind === "approval.resolved"
            || activity.kind === "user-input.resolved"
            || activity.kind === "provider.approval.respond.failed"
            || activity.kind === "provider.user-input.respond.failed";
        if (!terminal)
            return;
        const identity = requestActivityId(activity);
        if (handledRequestActivities[identity] === true)
            return;
        const handled = Object.assign({}, handledRequestActivities);
        handled[identity] = true;
        handledRequestActivities = handled;

        const payload = activity.payload && typeof activity.payload === "object"
            ? activity.payload : {};
        const requestId = typeof payload.requestId === "string" ? payload.requestId : "";
        if (requestId === "")
            return;
        if (activity.kind === "approval.resolved") {
            clearAction(actionKey("approval", threadId, requestId));
        } else if (activity.kind === "user-input.resolved") {
            clearAction(actionKey("input", threadId, requestId));
            clearUserInputDraft(threadId, requestId);
        } else if (activity.kind === "provider.approval.respond.failed") {
            failAction(actionKey("approval", threadId, requestId),
                typeof payload.detail === "string" ? payload.detail : activity.summary);
        } else if (activity.kind === "provider.user-input.respond.failed") {
            failAction(actionKey("input", threadId, requestId),
                typeof payload.detail === "string" ? payload.detail : activity.summary);
        }
    }

    // Mirrors the reference client's pending approval/user-input derivation.
    function recomputePendingRequests() {
        const approvals = {};
        const inputs = {};
        const activities = sortedHistory(detailActivities);
        for (const activity of activities) {
            const payload = activity && activity.payload && typeof activity.payload === "object"
                ? activity.payload : {};
            const requestId = typeof payload.requestId === "string" ? payload.requestId : "";
            if (requestId !== "") {
                if (activity.kind === "approval.requested") {
                    approvals[requestId] = {
                        requestId: requestId,
                        kind: payload.requestKind === "file-read"
                            || payload.requestKind === "file-change"
                            || payload.requestKind === "command"
                            ? payload.requestKind : approvalKind(payload.requestType),
                        detail: typeof payload.detail === "string" ? payload.detail : "",
                        createdAt: activity.createdAt ?? ""
                    };
                } else if (activity.kind === "approval.resolved") {
                    delete approvals[requestId];
                } else if (activity.kind === "provider.approval.respond.failed"
                           && stalePendingFailure(payload.detail)) {
                    delete approvals[requestId];
                } else if (activity.kind === "user-input.requested") {
                    const questions = parseInputQuestions(payload);
                    if (questions) {
                        inputs[requestId] = {
                            requestId: requestId,
                            createdAt: activity.createdAt ?? "",
                            questions: questions
                        };
                    }
                } else if (activity.kind === "user-input.resolved") {
                    delete inputs[requestId];
                } else if (activity.kind === "provider.user-input.respond.failed"
                           && stalePendingFailure(payload.detail)) {
                    delete inputs[requestId];
                }
            }
            reconcileRequestActivity(activity, detailThreadId);
        }
        detailApprovals = Object.values(approvals)
            .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
        detailPendingInputs = Object.values(inputs)
            .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
    }

    function recomputeDetailDerived() {
        const messages = sortedHistory(detailMessages);
        let assistant = null;
        for (const message of messages) {
            if (message && message.role === "assistant" && typeof message.text === "string"
                    && message.text.trim() !== "")
                assistant = message;
        }
        detailLatestAssistant = assistant;

        const ignoredKinds = {
            "approval.requested": true,
            "approval.resolved": true,
            "user-input.requested": true,
            "user-input.resolved": true,
            "turn.plan.updated": true,
            "tool.started": true,
            "task.started": true,
            "context-window.updated": true
        };
        let latestActivity = null;
        for (const activity of sortedHistory(detailActivities)) {
            if (!activity || typeof activity.summary !== "string"
                    || activity.summary.trim() === "")
                continue;
            if (activity.tone !== "error" && (ignoredKinds[activity.kind] === true
                    || activity.summary === "Checkpoint captured"))
                continue;
            latestActivity = activity;
        }
        if (detailSession && detailSession.status === "error"
                && typeof detailSession.lastError === "string"
                && detailSession.lastError.trim() !== "") {
            const sessionError = {
                tone: "error",
                kind: "session.error",
                summary: detailSession.lastError,
                createdAt: detailSession.updatedAt ?? ""
            };
            if (!latestActivity || historyCompare(latestActivity, sessionError) <= 0)
                latestActivity = sessionError;
        }
        detailLatestActivity = latestActivity;

        const plans = (Array.isArray(detailProposedPlans) ? detailProposedPlans.slice() : [])
            .filter(plan => plan && typeof plan === "object")
            .sort((left, right) => {
                const lm = parseMs(left?.updatedAt ?? left?.createdAt);
                const rm = parseMs(right?.updatedAt ?? right?.createdAt);
                if (!isNaN(lm) && !isNaN(rm) && lm !== rm)
                    return lm - rm;
                return (left?.id ?? "").localeCompare(right?.id ?? "");
            });
        let latestPlan = null;
        const latestTurnId = detailLatestTurn ? detailLatestTurn.turnId : null;
        if (latestTurnId) {
            const matchingPlans = plans.filter(plan => plan.turnId === latestTurnId);
            if (matchingPlans.length > 0)
                latestPlan = matchingPlans[matchingPlans.length - 1];
        }
        if (!latestPlan && plans.length > 0)
            latestPlan = plans[plans.length - 1];
        detailActionablePlan = latestPlan
            && (latestPlan.implementedAt === null || latestPlan.implementedAt === undefined)
            ? latestPlan : null;

        const ready = (Array.isArray(detailCheckpoints) ? detailCheckpoints.slice() : [])
            .filter(checkpoint => checkpoint && checkpoint.status === "ready")
            .sort(historyCompare);
        if (ready.length === 0) {
            detailCheckpointSummary = null;
            if (detailDiff.checkpointRef !== "") {
                cancelActionRequests(actionKey("diff", detailThreadId, ""));
                detailDiff = ({ checkpointRef: "", loading: false, error: "", text: "",
                    fullText: "", truncated: false, totalChars: 0, totalLines: 0 });
            }
        } else {
            const checkpoint = ready[ready.length - 1];
            const files = Array.isArray(checkpoint.files) ? checkpoint.files : [];
            let additions = 0, deletions = 0;
            const filenames = [];
            for (const file of files) {
                if (!file || typeof file !== "object")
                    continue;
                if (typeof file.additions === "number" && isFinite(file.additions))
                    additions += Math.max(0, file.additions);
                if (typeof file.deletions === "number" && isFinite(file.deletions))
                    deletions += Math.max(0, file.deletions);
                if (typeof file.path === "string" && file.path !== "")
                    filenames.push(file.path);
            }
            detailCheckpointSummary = Object.assign({}, checkpoint, {
                fileCount: files.length,
                additions: additions,
                deletions: deletions,
                filenames: filenames.slice(0, 3)
            });
            if (detailDiff.checkpointRef !== ""
                    && detailDiff.checkpointRef !== checkpoint.checkpointRef) {
                cancelActionRequests(actionKey("diff", detailThreadId, ""));
                detailDiff = ({ checkpointRef: "", loading: false, error: "", text: "",
                    fullText: "", truncated: false, totalChars: 0, totalLines: 0 });
            }
        }
    }

    function recomputeDetail() {
        recomputePendingRequests();
        recomputeDetailDerived();
    }

    function loadFullThreadDiff(threadId, checkpoint) {
        const key = actionKey("diff", threadId, "");
        if (!canRead)
            return rejectAction(key, "This pairing cannot read thread data", false);
        if (!checkpoint || checkpoint.status !== "ready"
                || typeof checkpoint.checkpointTurnCount !== "number")
            return rejectAction(key, "No ready checkpoint is available", false);
        if (!Helpers.canBeginAction(actionStates, key))
            return "";
        beginAction(key, "", false);
        detailDiff = ({ checkpointRef: checkpoint.checkpointRef ?? "", loading: true,
            error: "", text: "", fullText: "", truncated: false,
            totalChars: 0, totalLines: 0 });
        return requestOnce("orchestration.getFullThreadDiff", {
            threadId: threadId,
            toTurnCount: checkpoint.checkpointTurnCount,
            ignoreWhitespace: false
        }, value => {
            if (root.detailThreadId !== threadId
                    || root.detailDiff.checkpointRef !== (checkpoint.checkpointRef ?? "")
                    || root.detailCheckpointSummary?.checkpointRef !== checkpoint.checkpointRef) {
                root.clearAction(key);
                return;
            }
            if (!value || typeof value.diff !== "string") {
                root.failAction(key, "Malformed diff response");
                root.detailDiff = Object.assign({}, root.detailDiff, {
                    loading: false, error: "Malformed diff response"
                });
                return;
            }
            const rendered = Helpers.truncateDiff(value.diff);
            root.detailDiff = Object.assign({
                checkpointRef: checkpoint.checkpointRef ?? "", loading: false, error: "",
                fullText: value.diff
            }, rendered);
            root.clearAction(key);
        }, error => {
            if (root.detailThreadId !== threadId
                    || root.detailDiff.checkpointRef !== (checkpoint.checkpointRef ?? "")) {
                root.clearAction(key);
                return;
            }
            root.failAction(key, error);
            root.detailDiff = Object.assign({}, root.detailDiff, {
                loading: false, error: error
            });
        }, { actionKey: key, fallback: "Diff unavailable" });
    }

    function reconcileCommandEvent(event) {
        if (!event || typeof event.commandId !== "string" || event.commandId === "")
            return;
        for (const key in actionStates) {
            const current = actionStates[key];
            if (!current || current.commandId !== event.commandId)
                continue;
            // A subscription event may race ahead of dispatchCommand's RPC
            // response. The batch owns live action progress; clearing it here
            // could otherwise prevent the next sequenced command from running.
            if (current.pending === true)
                return;
            if (current.awaitResolution === true
                    && (event.type === "thread.approval-response-requested"
                        || event.type === "thread.user-input-response-requested"))
                return;
            clearAction(key);
            return;
        }
    }

    function applyDetailEvent(event, threadId) {
        if (!event || typeof event !== "object")
            return;
        const payload = event.payload && typeof event.payload === "object" ? event.payload : {};
        if (typeof payload.threadId === "string" && payload.threadId !== threadId)
            return;
        reconcileCommandEvent(event);

        switch (event.type) {
        case "thread.message-sent": {
            if (typeof payload.messageId === "string") {
                const existing = detailMessages.find(message =>
                    message && message.id === payload.messageId);
                const incomingText = typeof payload.text === "string" ? payload.text : "";
                const existingText = existing && typeof existing.text === "string"
                    ? existing.text : "";
                const text = existing
                    ? (payload.streaming === true ? existingText + incomingText
                        : incomingText !== "" ? incomingText : existingText)
                    : incomingText;
                const message = {
                    id: payload.messageId,
                    role: payload.role ?? "system",
                    text: text,
                    attachments: Array.isArray(payload.attachments) ? payload.attachments
                        : (existing?.attachments ?? []),
                    turnId: payload.turnId ?? null,
                    streaming: payload.streaming === true,
                    createdAt: existing?.createdAt ?? payload.createdAt ?? event.occurredAt ?? "",
                    updatedAt: payload.updatedAt ?? event.occurredAt ?? ""
                };
                detailMessages = upsertHistory(detailMessages, message, "id");
                confirmDraftMessage(threadId, payload.messageId);
            }
            break;
        }
        case "thread.activity-appended":
            if (payload.activity && typeof payload.activity === "object")
                detailActivities = upsertHistory(detailActivities, payload.activity, "id");
            break;
        case "thread.proposed-plan-upserted":
            if (payload.proposedPlan && typeof payload.proposedPlan === "object")
                detailProposedPlans = upsertHistory(detailProposedPlans,
                    payload.proposedPlan, "id");
            break;
        case "thread.turn-diff-completed": {
            const checkpoint = {
                turnId: payload.turnId,
                checkpointTurnCount: payload.checkpointTurnCount ?? 0,
                checkpointRef: payload.checkpointRef,
                status: payload.status,
                files: Array.isArray(payload.files) ? payload.files : [],
                assistantMessageId: payload.assistantMessageId ?? null,
                completedAt: payload.completedAt ?? event.occurredAt ?? ""
            };
            detailCheckpoints = upsertHistory(detailCheckpoints, checkpoint, "checkpointRef");
            break;
        }
        case "thread.session-set":
            detailSession = payload.session ?? null;
            break;
        case "thread.reverted":
            // Revert invalidates message, activity, plan, and checkpoint
            // histories. A fresh snapshot is the only safe reconciliation.
            pendingDetailResubscribeId = threadId;
            detailLoading = true;
            detailResubscribeTimer.restart();
            break;
        case "thread.deleted":
            closeDetail();
            return;
        }
        recomputeDetail();
    }

    function applyDetailSnapshot(snapshot, threadId) {
        const thread = snapshot && snapshot.thread;
        if (!thread || typeof thread !== "object" || (thread.id && thread.id !== threadId)) {
            detailLoading = false;
            detailError = "Malformed thread snapshot";
            return;
        }
        detailMessages = sortedHistory(thread.messages);
        for (const message of detailMessages) {
            if (message && typeof message.id === "string")
                confirmDraftMessage(threadId, message.id);
        }
        detailActivities = sortedHistory(thread.activities);
        detailProposedPlans = sortedHistory(thread.proposedPlans);
        detailCheckpoints = sortedHistory(thread.checkpoints);
        detailSession = thread.session ?? null;
        detailLatestTurn = thread.latestTurn ?? null;
        detailLoading = false;
        detailError = "";
        recomputeDetail();
    }

    function stopDetailRequest() {
        if (detailReqId === "")
            return;
        socketLoader.item?.sendText(JSON.stringify({ _tag: "Interrupt", requestId: detailReqId }));
        delete rpcHandlers[detailReqId];
        detailReqId = "";
    }

    function startDetailSubscription(threadId) {
        detailResubscribeTimer.stop();
        pendingDetailResubscribeId = "";
        stopDetailRequest();
        cancelActionRequests(actionKey("diff", threadId, ""));
        resetDetailData();
        if (state !== "connected" || threadId === "")
            return;

        detailLoading = true;
        const shell = threadMap[threadId];
        if (shell) {
            detailSession = shell.session ?? null;
            detailLatestTurn = shell.latestTurn ?? null;
        }
        const id = String(nextReqId++);
        detailReqId = id;
        rpcHandlers[id] = {
            item: item => {
                if (root.detailReqId !== id || root.detailThreadId !== threadId)
                    return;
                if (item.kind === "snapshot")
                    root.applyDetailSnapshot(item.snapshot, threadId);
                else if (item.kind === "event")
                    root.applyDetailEvent(item.event, threadId);
            },
            exit: msg => {
                if (root.detailReqId !== id)
                    return;
                root.detailReqId = "";
                root.detailLoading = false;
                if (msg.exit && msg.exit._tag === "Failure")
                    root.detailError = root.failureMessage(msg, "Thread details unavailable");
            }
        };
        sendRequest(id, "orchestration.subscribeThread", { threadId: threadId });
    }

    function openDetail(threadId) {
        if (typeof threadId !== "string" || threadId === "") {
            closeDetail();
            return;
        }
        if (detailThreadId === threadId && detailReqId !== "")
            return;
        if (detailThreadId !== "" && detailThreadId !== threadId)
            cancelActionRequests(actionKey("diff", detailThreadId, ""));
        detailThreadId = threadId;
        startDetailSubscription(threadId);
    }

    function closeDetail() {
        if (detailThreadId !== "")
            cancelActionRequests(actionKey("diff", detailThreadId, ""));
        detailResubscribeTimer.stop();
        pendingDetailResubscribeId = "";
        stopDetailRequest();
        detailThreadId = "";
        resetDetailData();
    }

    Timer {
        id: detailResubscribeTimer
        interval: 1
        onTriggered: {
            const threadId = root.pendingDetailResubscribeId;
            root.pendingDetailResubscribeId = "";
            if (threadId !== "" && root.detailThreadId === threadId
                    && root.state === "connected")
                root.startDetailSubscription(threadId);
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
                if (root.state === "connected" || root.state === "connecting") {
                    root.abortPendingRpcs();
                    root.configLoading = false;
                    root.configReady = false;
                    root.scheduleRetry();
                }
            }
        }
    }
}
