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
    property bool shellReady: false

    // Derived, popover-ready: the active inbox only (settled and snoozed
    // threads are dropped), sorted by urgency then recency.
    property var threads: []
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

    readonly property bool paired: host !== "" && accessToken !== ""
    readonly property string pairHint: "python3 ~/.config/quickshell/scripts/t3-pair.py '<pairing-url>'"

    // ---- classification ------------------------------------------------

    // Days of quiet after which a thread settles itself. Mirrors the web
    // client's sidebar setting (its default is 3); 0 disables auto-settle.
    property int autoSettleAfterDays: 3

    readonly property int dayMs: 86400000
    // A turn.start is adopted by a session within seconds; past this the
    // message is a failed start, not pending work.
    readonly property int queuedTurnGraceMs: 120000

    // Bumped once a minute so settledness and the relative time labels
    // follow the clock — both move without any server event.
    property double nowMs: Date.now()

    function parseMs(iso) {
        return iso ? Date.parse(iso) : NaN;
    }

    // Newest real activity on a thread (reference: threadLastActivityAt).
    function lastActivityMs(t) {
        const turn = t.latestTurn;
        const stamps = [t.latestUserMessageAt,
                        turn ? turn.requestedAt : null,
                        turn ? turn.startedAt : null,
                        turn ? turn.completedAt : null];
        let latest = NaN;
        for (const s of stamps) {
            const ms = parseMs(s);
            if (!isNaN(ms) && (isNaN(latest) || ms > latest))
                latest = ms;
        }
        return latest;
    }

    // A user message no session has adopted yet: the turn exists but none
    // of the status fields show it, so it has to be detected as a message
    // strictly newer than every timestamp on the latest turn.
    function hasQueuedTurnStart(t, now) {
        const msg = parseMs(t.latestUserMessageAt);
        if (isNaN(msg))
            return false;
        // A failed start is already visible as an error.
        if (t.session && t.session.status === "error")
            return false;
        // Bounded both ways: the sender's clock may run ahead of ours.
        if (Math.abs(now - msg) > queuedTurnGraceMs)
            return false;
        const turn = t.latestTurn;
        if (!turn)
            return true;
        for (const stamp of [turn.requestedAt, turn.startedAt, turn.completedAt]) {
            const ms = parseMs(stamp);
            if (!isNaN(ms) && ms >= msg)
                return false;
        }
        return true;
    }

    // Mirrors the reference client's effectiveSettled, which is what the
    // web sidebar partitions on: blocked or live work stays active whatever
    // the flags say, then an explicit settle/unsettle wins, then a thread
    // quiet past the window settles itself. The reference's third input —
    // pull request state — isn't subscribed here, so a merged PR only
    // settles its thread once the thread also goes quiet.
    function isSettled(t, now) {
        if (t.hasPendingApprovals || t.hasPendingUserInput)
            return false;
        const sess = t.session ? t.session.status : "";
        if (sess === "starting" || sess === "running")
            return false;
        if (hasQueuedTurnStart(t, now)) {
            // Unless the server already ruled on that message by accepting
            // a settle stamped after it.
            const adjudicated = t.settledOverride === "settled"
                && parseMs(t.settledAt) >= parseMs(t.latestUserMessageAt);
            if (!adjudicated)
                return false;
        }
        if (t.settledOverride === "settled")
            return true;
        if (t.settledOverride === "active")
            return false;
        if (autoSettleAfterDays <= 0)
            return false;
        const last = lastActivityMs(t);
        return !isNaN(last) && last < now - autoSettleAfterDays * dayMs;
    }

    // Shelved until its wake time — unless the thread raises its hand:
    // blocked on the user, freshly failed, or finished a run after the
    // snooze was set.
    function isSnoozed(t, now) {
        const wake = parseMs(t.snoozedUntil);
        if (isNaN(wake) || wake <= now)
            return false;
        if (t.hasPendingApprovals || t.hasPendingUserInput)
            return false;
        const since = parseMs(t.snoozedAt);
        if (t.session && t.session.status === "error"
                && (isNaN(since) || parseMs(t.session.updatedAt) > since))
            return false;
        const turn = t.latestTurn;
        if (!isNaN(since) && turn && turn.state === "completed"
                && parseMs(turn.completedAt) > since)
            return false;
        return true;
    }

    // "attention" | "running" | "error" | "done" | "idle". Only ever asked
    // of active threads — settledness is decided before this runs.
    function threadClass(t) {
        if (t.hasPendingApprovals || t.hasPendingUserInput)
            return "attention";
        const sess = t.session ? t.session.status : "";
        const turn = t.latestTurn ? t.latestTurn.state : "";
        if (sess === "starting" || sess === "running" || turn === "running")
            return "running";
        if (sess === "error" || turn === "error")
            return "error";
        if (turn === "completed")
            return "done";
        return "idle";
    }

    function threadCanPrompt(t, now) {
        if (t.hasPendingApprovals || t.hasPendingUserInput
                || t.hasActionableProposedPlan === true)
            return false;
        const sess = t.session ? t.session.status : "";
        const turn = t.latestTurn ? t.latestTurn.state : "";
        if (sess === "starting" || sess === "running" || turn === "running")
            return false;
        return !hasQueuedTurnStart(t, now);
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
        const rank = { attention: 0, error: 1, running: 2, done: 3, idle: 4 };
        const now = Date.now();
        let running = 0, attention = 0, done = 0, settled = 0, snoozed = 0;
        const list = [], hidden = [];
        for (const id in threadMap) {
            const t = threadMap[id];
            if (t.archivedAt)
                continue;
            // Put-away threads belong to the web client's tail, not here.
            if (isSnoozed(t, now)) {
                snoozed++;
                hidden.push(t.id);
                continue;
            }
            if (isSettled(t, now)) {
                settled++;
                hidden.push(t.id);
                continue;
            }
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
                planReady: t.hasActionableProposedPlan === true,
                sessionStatus: t.session && typeof t.session.status === "string"
                    ? t.session.status : "",
                canPrompt: threadCanPrompt(t, now),
                updatedAt: t.updatedAt
            });
        }
        list.sort((a, b) => (rank[a.cls] - rank[b.cls])
            || (Date.parse(b.updatedAt) - Date.parse(a.updatedAt)));

        const sig = settled + "/" + snoozed + "/" + JSON.stringify(list);
        if (sig === listSignature)
            return;
        listSignature = sig;

        // Hidden threads keep a class of their own so one that comes back —
        // the server un-settles on a new approval or question — reads as a
        // transition and still raises its toast.
        const next = {};
        for (const id of hidden)
            next[id] = "hidden";
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
        settledCount = settled;
        snoozedCount = snoozed;

        // Shell updates carry the freshest session/latest-turn summary even
        // while the detailed history stream is catching up.
        const selected = threadMap[detailThreadId];
        if (selected) {
            detailSession = selected.session ?? null;
            detailLatestTurn = selected.latestTurn ?? null;
            recomputeDetailDerived();
        }
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
        sendRequest(shellReqId, "orchestration.subscribeShell", {});
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
            shellReady = true;
            return true;
        }
        case "synchronized":
            shellReady = true;
            return false;
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

    // Returns the command id when queued and an empty string when it could
    // not be sent. Approval/input actions remain pending after RPC acceptance
    // until their provider resolution activity arrives.
    function dispatch(command, key, awaitResolution) {
        if (actionStates[key]?.pending === true)
            return "";
        if (state !== "connected" || !socketLoader.item) {
            putActionState(key, {
                pending: false,
                error: "Not connected",
                commandId: "",
                awaitResolution: awaitResolution === true,
                startedAt: Date.now()
            });
            return "";
        }

        const commandId = command.commandId ?? genId();
        command.commandId = commandId;
        beginAction(key, commandId, awaitResolution);
        const id = String(nextReqId++);
        rpcHandlers[id] = {
            exit: msg => {
                if (msg.exit && msg.exit._tag === "Failure") {
                    const error = root.failureMessage(msg, "Command rejected");
                    root.failAction(key, error);
                    console.warn("t3code: command rejected:", error);
                } else if (!awaitResolution) {
                    root.clearAction(key);
                }
            }
        };
        sendRequest(id, "orchestration.dispatchCommand", command);
        return commandId;
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
        return dispatch({
            type: "thread.settle",
            commandId: genId(),
            threadId: threadId
        }, actionKey("settle", threadId, ""), false);
    }

    function interrupt(threadId) {
        return dispatch({
            type: "thread.turn.interrupt",
            commandId: genId(),
            threadId: threadId,
            createdAt: new Date().toISOString()
        }, actionKey("interrupt", threadId, ""), false);
    }

    function startTurn(threadId, text) {
        const t = threadMap[threadId];
        const key = actionKey("prompt", threadId, "");
        if (!t || typeof text !== "string" || text.trim() === "")
            return "";
        return dispatch({
            type: "thread.turn.start",
            commandId: genId(),
            threadId: threadId,
            message: {
                messageId: genId(),
                role: "user",
                text: text.trim(),
                attachments: []
            },
            runtimeMode: t.runtimeMode ?? "full-access",
            interactionMode: t.interactionMode ?? "default",
            createdAt: new Date().toISOString()
        }, key, false);
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
        }
    }

    function recomputeDetail() {
        recomputePendingRequests();
        recomputeDetailDerived();
    }

    function reconcileCommandEvent(event) {
        if (!event || typeof event.commandId !== "string" || event.commandId === "")
            return;
        for (const key in actionStates) {
            const current = actionStates[key];
            if (!current || current.commandId !== event.commandId)
                continue;
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
        detailThreadId = threadId;
        startDetailSubscription(threadId);
    }

    function closeDetail() {
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
                if (root.state === "connected" || root.state === "connecting")
                    root.scheduleRetry();
            }
        }
    }
}
