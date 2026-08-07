pragma Singleton
import QtQuick
import Quickshell
import "T3CodeHelpers.js" as Helpers

// Request/response over the T3 socket, and the state machine that tracks a
// dispatched command until the server confirms it.
//
// This is the layer between the transport (Common/T3Connection.qml, which
// knows only frames) and the domain (Common/T3Code.qml, which knows threads).
// It owns request ids, the in-flight handler table, the deadline sweep that
// expires both, and `actionStates` — the per-button pending/error state the
// popover reads.
//
// T3Code routes incoming frames here by request id; anything on the shell
// stream is domain traffic and never reaches this file.
Singleton {
    id: root

    // Per-command UI state, keyed by actionKey(kind, threadId, requestId):
    // { pending, error, commandId, ... }. A finished entry is left in place so
    // the button can keep showing why it failed, which is why the deadline
    // sweep below only ever looks at pending ones.
    property var actionStates: ({})
    readonly property int actionTimeoutMs: 15000

    function putRpcHandler(id, handler) {
        dropRpcHandler(id);
        rpcHandlers[id] = handler;
        if (typeof handler.deadline === "number")
            rpcDeadlineCount++;
    }

    function dropRpcHandler(id) {
        const handler = rpcHandlers[id];
        if (handler === undefined)
            return;
        delete rpcHandlers[id];
        if (typeof handler.deadline === "number")
            rpcDeadlineCount--;
    }

    function clearRpcHandlers() {
        rpcHandlers = {};
        rpcDeadlineCount = 0;
    }

    function genId() {
        let s = "";
        for (let i = 0; i < 32; i++)
            s += Math.floor(Math.random() * 16).toString(16);
        return s;
    }

    function sendRequest(id, tag, payload) {
        if (T3Connection.state !== "connected")
            return false;
        T3Connection.send(JSON.stringify({
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
        if (T3Connection.state !== "connected") {
            onFailure?.("Not connected");
            return "";
        }
        const id = String(nextReqId++);
        const opts = options ?? {};
        const handler = {
            value: undefined,
            deadline: Date.now() + (opts.timeoutMs ?? actionTimeoutMs),
            actionKey: opts.actionKey ?? "",
            item: value => {
                handler.value = value;
                // Streams that report progress (git.runStackedAction) stay
                // alive as long as chunks keep arriving.
                if (opts.slidingDeadline === true)
                    handler.deadline = Date.now() + (opts.timeoutMs ?? actionTimeoutMs);
                opts.onItem?.(value);
            },
            exit: msg => {
                if (msg.exit && msg.exit._tag === "Failure")
                    onFailure?.(root.failureMessage(msg, opts.fallback ?? "Request failed"));
                else {
                    // Unary Effect RPCs (including server.getConfig and the
                    // full-diff request) return their result on Success.value.
                    // Streams exit with a null value and instead populate
                    // `handler.value` through their final Chunk.
                    const exitValue = msg.exit ? msg.exit.value : undefined;
                    const value = exitValue !== undefined && exitValue !== null
                        ? exitValue : handler.value;
                    onSuccess?.(value);
                }
            },
            timeout: () => onFailure?.("Request timed out"),
            disconnect: () => onFailure?.("Disconnected before confirmation")
        };
        putRpcHandler(id, handler);
        if (!sendRequest(id, tag, payload)) {
            dropRpcHandler(id);
            onFailure?.("Not connected");
            return "";
        }
        return id;
    }

    // Every in-flight request is gone. The detail subsystem listens so it can
    // forget the subscription id it was holding; this layer does not know what
    // that id was for.
    signal aborted()

    function abortPendingRpcs() {
        const handlers = rpcHandlers;
        clearRpcHandlers();
        for (const id in handlers)
            handlers[id].disconnect?.();
        aborted();
    }


    // Deadline sweep for in-flight RPCs and pending actions. Both are empty
    // most of the time, so the tick is gated on there being something to
    // expire: rpcDeadlineCount notifies where rpcHandlers cannot, and
    // expireActionStates only ever touches pending entries — a finished
    // action left in place to show its error must not keep this running.
    Timer {
        interval: 500
        repeat: true
        running: T3Connection.state === "connected"
            && (root.rpcDeadlineCount > 0
                || Object.values(root.actionStates).some(state => state && state.pending === true))
        onTriggered: {
            const now = Date.now();
            for (const id in root.rpcHandlers) {
                const handler = root.rpcHandlers[id];
                if (handler.deadline === undefined || now < handler.deadline)
                    continue;
                T3Connection.send(JSON.stringify({ _tag: "Interrupt", requestId: id }));
                root.dropRpcHandler(id);
                handler.timeout?.();
            }
            const expired = Helpers.expireActionStates(root.actionStates, now,
                root.actionTimeoutMs);
            if (expired.expiredKeys.length > 0)
                root.actionStates = expired.states;
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

    function beginAction(key, commandId, awaitResolution, timeoutMs) {
        const state = {
            pending: true,
            error: "",
            commandId: commandId,
            awaitResolution: awaitResolution === true,
            startedAt: Date.now()
        };
        if (typeof timeoutMs === "number" && timeoutMs > 0)
            state.timeoutMs = timeoutMs;
        putActionState(key, state);
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
            T3Connection.send(JSON.stringify({ _tag: "Interrupt", requestId: id }));
            dropRpcHandler(id);
        }
        clearAction(key);
    }

    function failureMessage(msg, fallback) {
        const found = Helpers.findErrorText(msg ? msg.exit : null, 0);
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
        if (!T3Connection.canOperate)
            return rejectAction(key, "This pairing is read-only", opts.awaitResolution);
        if (T3Connection.state !== "connected")
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


    readonly property string shellReqId: "1"
    property int nextReqId: 2
    // requestId → { item(value), exit(msg) } for non-shell streams.
    property var rpcHandlers: ({})
    // rpcHandlers is mutated in place (added and deleted by request id), and
    // an in-place mutation never re-evaluates a binding. This is the notifying
    // mirror the deadline sweep below watches, so every add and delete goes
    // through the three functions here. Only handlers that actually carry a
    // deadline count: an open detail subscription has none and must not keep
    // the sweep awake for as long as the popover shows a thread.
    property int rpcDeadlineCount: 0
}
