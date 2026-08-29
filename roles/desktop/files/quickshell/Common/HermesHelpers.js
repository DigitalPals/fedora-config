// Pure normalization and projection helpers for the Hermes menubar client.
// Keep this file free of Qt APIs: bridge payloads are deliberately normalized
// here so both QML and Node tests exercise the same compatibility boundary.

var WORKING_STATES = ["working", "running", "thinking", "generating", "busy"];
var ATTENTION_STATES = ["approval", "clarify", "input", "sudo", "secret", "waiting"];
var TERMINAL_TOOL_STATES = ["completed", "complete", "done", "failed", "error",
    "cancelled", "canceled", "interrupted"];

function object(value) {
    return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function array(value) {
    return Array.isArray(value) ? value : [];
}

function string(value, fallback) {
    if (typeof value === "string")
        return value;
    if (typeof value === "number" || typeof value === "boolean")
        return String(value);
    return fallback || "";
}

function firstString() {
    for (var i = 0; i < arguments.length; i++) {
        var value = string(arguments[i], "").trim();
        if (value !== "")
            return value;
    }
    return "";
}

function number(value, fallback) {
    return typeof value === "number" && isFinite(value) ? value : fallback;
}

function bool(value, fallback) {
    return typeof value === "boolean" ? value : fallback;
}

function compactState(value) {
    return string(value, "idle").trim().toLowerCase().replace(/[._ -]+/g, "-");
}

function canonicalStatus(value) {
    var state = compactState(value);
    if (WORKING_STATES.indexOf(state) >= 0 || state.indexOf("tool-") === 0)
        return "working";
    if (ATTENTION_STATES.indexOf(state) >= 0 || state.indexOf("needs-") === 0)
        return "attention";
    if (["failed", "failure", "error", "crashed"].indexOf(state) >= 0)
        return "error";
    if (["complete", "completed", "done", "finished", "success"].indexOf(state) >= 0)
        return "done";
    if (["offline", "disconnected", "unavailable"].indexOf(state) >= 0)
        return "offline";
    if (["queued", "pending"].indexOf(state) >= 0)
        return "queued";
    return "idle";
}

function normalizeConversation(raw, index) {
    var value = object(raw);
    var session = object(value.session);
    var id = firstString(value.sessionId, value.session_id, value.id,
        session.sessionId, session.session_id, session.id,
        "conversation-" + number(index, 0));
    var statusValue = firstString(value.status, value.state, value.activityState,
        session.status, session.state, "idle");
    if (value.attention || session.attention)
        statusValue = "attention";
    else if (value.isStreaming === true || value.is_streaming === true
            || firstString(value.activeStreamId, value.active_stream_id,
                session.activeStreamId, session.active_stream_id) !== "")
        statusValue = "working";
    var status = canonicalStatus(statusValue);
    var unread = Math.max(0, Math.floor(number(value.unread,
        number(value.unreadCount, value.hasUnread === true ? 1 : 0))));
    return {
        id: id,
        sessionId: id,
        title: firstString(value.title, value.name, session.title,
            "Untitled chat"),
        profile: firstString(value.profile, value.profileName, session.profile),
        model: firstString(value.model, value.modelName, session.model),
        workspace: firstString(value.workspace, value.cwd, session.workspace),
        source: firstString(value.sourceLabel, value.source_label,
            value.sessionSource, value.session_source, value.sourceTag,
            value.source_tag),
        readOnly: bool(value.readOnly, bool(value.read_only,
            bool(session.readOnly, bool(session.read_only, false)))),
        messageCount: Math.max(0, Math.floor(number(value.messageCount,
            number(value.message_count, number(session.messageCount,
                number(session.message_count, 0)))))),
        status: status,
        rawStatus: statusValue,
        statusText: firstString(value.statusText, value.activity, value.detail,
            session.statusText, status === "working" ? "Hermes is working…"
                : status === "attention" ? "Hermes needs you" : "Ready"),
        unread: unread,
        requestCount: Math.max(0, Math.floor(number(value.requestCount,
            number(value.pendingRequests, status === "attention" ? 1 : 0)))),
        updatedAt: firstString(value.updatedAt, value.lastActivityAt,
            value.updated_at, value.last_message_at, session.updatedAt,
            session.updated_at, value.createdAt, value.created_at),
        createdAt: firstString(value.createdAt, value.created_at,
            session.createdAt, session.created_at),
        error: firstString(value.error, value.lastError, session.error)
    };
}

function conversationPriority(conversation) {
    switch (conversation && conversation.status) {
    case "attention": return 0;
    case "error": return 1;
    case "working": return 2;
    case "queued": return 3;
    case "done": return 4;
    default: return 5;
    }
}

function parseTime(value) {
    if (typeof value === "number" && isFinite(value))
        return value < 100000000000 ? value * 1000 : value;
    var parsed = typeof value === "string"
        ? (/^\d+(?:\.\d+)?$/.test(value.trim())
            ? Number(value) * (Number(value) < 100000000000 ? 1000 : 1)
            : Date.parse(value)) : NaN;
    return isNaN(parsed) ? 0 : parsed;
}

function sortedConversations(values) {
    return array(values).slice().sort(function(a, b) {
        var priority = conversationPriority(a) - conversationPriority(b);
        if (priority !== 0)
            return priority;
        var time = parseTime(b.updatedAt) - parseTime(a.updatedAt);
        if (time !== 0)
            return time;
        return string(a.title).localeCompare(string(b.title));
    });
}

function extractText(content) {
    if (typeof content === "string")
        return content;
    if (Array.isArray(content)) {
        var parts = [];
        for (var i = 0; i < content.length; i++) {
            var part = content[i];
            if (typeof part === "string")
                parts.push(part);
            else if (part && typeof part === "object") {
                var text = firstString(part.text, part.content, part.value);
                if (text !== "")
                    parts.push(text);
            }
        }
        return parts.join("\n");
    }
    if (content && typeof content === "object")
        return firstString(content.text, content.content, content.value);
    return "";
}

function normalizeRole(value) {
    var role = compactState(value);
    if (["human", "me", "you"].indexOf(role) >= 0)
        return "user";
    if (["agent", "hermes", "model"].indexOf(role) >= 0)
        return "assistant";
    if (["tool", "system"].indexOf(role) >= 0)
        return role;
    return role === "user" ? "user" : "assistant";
}

function normalizeMessage(raw, index) {
    var value = object(raw);
    var nested = object(value.message);
    if (Object.keys(nested).length > 0)
        value = Object.assign({}, nested, value);
    var text = extractText(value.text !== undefined ? value.text
        : value.content !== undefined ? value.content
            : value.delta !== undefined ? value.delta : value.message);
    var id = firstString(value.id, value.messageId, value.message_id,
        value.turnId, value.turn_id, value.itemId, value.item_id,
        "message-" + number(index, 0));
    return {
        id: id,
        role: normalizeRole(value.role || value.author || value.sender),
        text: text,
        createdAt: firstString(value.createdAt, value.created_at,
            value.timestamp, value.time),
        updatedAt: firstString(value.updatedAt, value.updated_at,
            value.timestamp, value.time),
        streaming: bool(value.streaming, bool(value.partial, false)),
        pending: bool(value.pending, false),
        error: firstString(value.error),
        model: firstString(value.model, value.modelName),
        parentId: firstString(value.parentId, value.parent_id,
            value.parentMessageId, value.parent_message_id)
    };
}

function messageList(value) {
    if (Array.isArray(value))
        return value;
    var data = object(value);
    if (Array.isArray(data.messages))
        return data.messages;
    if (Array.isArray(data.items))
        return data.items;
    if (Array.isArray(data.history))
        return data.history;
    return [];
}

function normalizeMessages(value) {
    return messageList(value).map(function(message, index) {
        return normalizeMessage(message, index);
    });
}

function upsertById(values, item) {
    var next = array(values).slice();
    var at = next.findIndex(function(current) { return current.id === item.id; });
    if (at < 0)
        next.push(item);
    else
        next[at] = Object.assign({}, next[at], item);
    return next;
}

function applyMessageEvent(values, type, payload) {
    var event = compactState(type);
    if (["message-snapshot", "message-list", "session-history", "history"].indexOf(event) >= 0)
        return normalizeMessages(payload);
    var current = array(values);
    var message = normalizeMessage(payload, current.length);
    if (event === "message-delta" || event === "assistant-delta" || event === "stream-delta") {
        var at = current.findIndex(function(item) { return item.id === message.id; });
        if (at < 0) {
            message.streaming = true;
            return current.concat([message]);
        }
        var next = current.slice();
        var previous = next[at];
        next[at] = Object.assign({}, previous, message, {
            text: string(previous.text) + string(message.text),
            streaming: true
        });
        return next;
    }
    if (event === "message-start" || event === "assistant-start")
        message.streaming = true;
    if (event === "message-complete" || event === "message-completed"
            || event === "assistant-complete")
        message.streaming = false;
    return upsertById(current, message);
}

function normalizeTool(raw, index) {
    var value = object(raw);
    var call = object(value.tool);
    if (Object.keys(call).length > 0)
        value = Object.assign({}, call, value);
    var status = compactState(value.status || value.state || "running");
    return {
        id: firstString(value.id, value.toolCallId, value.tool_call_id,
            value.callId, value.call_id,
            "tool-" + number(index, 0)),
        name: firstString(value.name, value.toolName, value.tool_name,
            value.function, "Tool"),
        label: firstString(value.label, value.title, value.description),
        status: status,
        detail: firstString(value.detail, value.summary, value.command, value.path),
        startedAt: firstString(value.startedAt, value.started_at,
            value.createdAt, value.created_at, value.timestamp),
        completedAt: firstString(value.completedAt, value.completed_at,
            value.updatedAt, value.updated_at),
        error: firstString(value.error, value.errorMessage, value.error_message),
        terminal: TERMINAL_TOOL_STATES.indexOf(status) >= 0
    };
}

function applyToolEvent(values, type, payload) {
    var next = array(values);
    var tool = normalizeTool(payload, next.length);
    var event = compactState(type);
    if (event.indexOf("completed") >= 0 || event.indexOf("complete") >= 0) {
        tool.status = "completed";
        tool.terminal = true;
    } else if (event.indexOf("failed") >= 0 || event.indexOf("error") >= 0) {
        tool.status = "error";
        tool.terminal = true;
    } else if (event.indexOf("cancel") >= 0 || event.indexOf("interrupt") >= 0) {
        tool.status = "interrupted";
        tool.terminal = true;
    }
    return upsertById(next, tool);
}

function normalizeOptions(value) {
    return array(value).map(function(option, index) {
        if (typeof option === "string")
            return { id: option, label: option, description: "", value: option };
        var raw = object(option);
        var label = firstString(raw.label, raw.title, raw.value, raw.id,
            "Option " + (index + 1));
        return {
            id: firstString(raw.id, raw.value, label),
            label: label,
            description: firstString(raw.description, raw.detail),
            value: raw.value !== undefined ? raw.value : firstString(raw.id, label)
        };
    });
}

function normalizeRequestKind(value) {
    var kind = compactState(value);
    if (kind.indexOf("clarif") >= 0 || kind === "input" || kind === "question")
        return "clarify";
    if (kind.indexOf("sudo") >= 0 || kind.indexOf("elevat") >= 0)
        return "sudo";
    if (kind.indexOf("secret") >= 0 || kind.indexOf("credential") >= 0)
        return "secret";
    return "approval";
}

function normalizeQuestion(raw, index) {
    var value = object(raw);
    var id = firstString(value.id, value.qid, value.questionId,
        value.question_id, "question-" + number(index, 0));
    return {
        id: id,
        prompt: firstString(value.prompt, value.question, value.text),
        header: firstString(value.header, value.title),
        options: normalizeOptions(value.options || value.choices),
        multiSelect: bool(value.multiSelect, bool(value.multi_select, false))
    };
}

function normalizeRequest(raw, index) {
    var value = object(raw);
    var nested = object(value.request);
    if (Object.keys(nested).length > 0)
        value = Object.assign({}, nested, value);
    var kind = normalizeRequestKind(value.kind || value.type || value.requestType);
    var questions = array(value.questions).map(function(question, questionIndex) {
        return normalizeQuestion(question, questionIndex);
    });
    var firstQuestion = questions.length > 0 ? object(questions[0]) : {};
    return {
        id: firstString(value.id, value.requestId, value.request_id,
            value.callId, value.call_id,
            "request-" + number(index, 0)),
        kind: kind,
        title: firstString(value.title, value.header, firstQuestion.header,
            kind === "clarify" ? "Hermes has a question"
                : kind === "sudo" ? "Administrator access"
                    : kind === "secret" ? "Credential needed" : "Approval needed"),
        prompt: firstString(value.prompt, value.question, value.message,
            firstQuestion.prompt, value.detail),
        detail: firstString(value.detail, value.description, value.command),
        secretName: firstString(value.secretName, value.secret_name, value.env_var,
            value.name, value.key),
        options: normalizeOptions(value.options || value.choices
            || firstQuestion.options),
        multiSelect: bool(value.multiSelect, bool(value.multi_select, false)),
        questions: questions,
        createdAt: firstString(value.createdAt, value.created_at, value.timestamp),
        resolved: bool(value.resolved, false),
        error: firstString(value.error)
    };
}

function applyRequestEvent(values, type, payload) {
    var current = array(values);
    var event = compactState(type);
    var request = normalizeRequest(payload, current.length);
    if (event.indexOf("resolved") >= 0 || event.indexOf("completed") >= 0
            || event.indexOf("cancel") >= 0 || event.indexOf("expired") >= 0
            || event.indexOf("expire") >= 0)
        return current.filter(function(item) { return item.id !== request.id; });
    return upsertById(current, request);
}

function eventType(value) {
    return string(value).trim().toLowerCase().replace(/[._ ]+/g, "-");
}

function sessionId(payload) {
    var value = object(payload);
    var session = object(value.session);
    return firstString(value.sessionId, value.session_id, session.id);
}

function statusVerb(value) {
    var raw = firstString(value).trim();
    if (raw === "")
        return "working";
    raw = raw.replace(/^Hermes\s+(?:is\s+)?/i, "").replace(/\.{3}|…/g, "").trim();
    var first = raw.split(/[ ·:—-]/)[0].toLowerCase();
    if (/^[a-z][a-z0-9_-]{1,24}$/.test(first))
        return first.replace(/_/g, " ");
    return "working";
}

function activityLabel(conversation, detailMode) {
    if (!conversation)
        return "idle";
    if (conversation.status === "attention")
        return "needs you";
    if (conversation.status === "error")
        return "error";
    if (conversation.status === "queued")
        return "queued";
    if (conversation.status === "done")
        return "done";
    if (conversation.status !== "working")
        return "idle";
    if (detailMode === "full" && conversation.statusText)
        return conversation.statusText;
    if (detailMode === "none" || detailMode === "generic")
        return "working…";
    return statusVerb(conversation.statusText) + "…";
}

function counts(conversations) {
    var result = { working: 0, attention: 0, errors: 0, done: 0, unread: 0 };
    array(conversations).forEach(function(conversation) {
        if (conversation.status === "working") result.working++;
        if (conversation.status === "attention") result.attention++;
        if (conversation.status === "error") result.errors++;
        if (conversation.status === "done") result.done++;
        result.unread += Math.max(0, number(conversation.unread, 0));
    });
    return result;
}

function relativeTime(value, now) {
    var then = parseTime(value);
    var current = typeof now === "number" && isFinite(now) ? now : Date.now();
    if (then <= 0)
        return "";
    var seconds = Math.max(0, Math.floor((current - then) / 1000));
    if (seconds < 10) return "now";
    if (seconds < 60) return seconds + "s";
    var minutes = Math.floor(seconds / 60);
    if (minutes < 60) return minutes + "m";
    var hours = Math.floor(minutes / 60);
    if (hours < 24) return hours + "h";
    var days = Math.floor(hours / 24);
    return days < 14 ? days + "d" : new Date(then).toLocaleDateString();
}

// Accept only an HTTP(S) WebUI base. User-info is rejected because the
// password has a dedicated, masked field and must never become part of a URL
// shown in the panel, a log, or bridge state.
function remoteWebUrl(value) {
    if (typeof value !== "string")
        return "";
    var trimmed = value.trim();
    if (!/^https?:\/\//i.test(trimmed)
            || /[\s\\\u0000-\u001f\u007f]/.test(trimmed))
        return "";
    var authority = trimmed.match(/^https?:\/\/([^/?#]+)/i);
    if (!authority || authority[1].indexOf("@") >= 0)
        return "";
    return trimmed.replace(/[/?#]+$/, "");
}

// The connected identity shown to the user is deliberately only the origin.
// Paths, queries, fragments and any attempted user-info are never reflected.
function remoteOrigin(value) {
    var safe = remoteWebUrl(value);
    if (safe === "")
        return "";
    var match = safe.match(/^(https?):\/\/([^/?#]+)/i);
    return match ? match[1].toLowerCase() + "://" + match[2] : "";
}

// An explicit bridge flag wins over a URL in the payload. Failed candidate
// logins include the attempted URL with configured=false; treating that URL as
// selected would make the local/remote backend choice ambiguous.
function remoteIsConfigured(raw) {
    var value = object(raw);
    if (typeof value.configured === "boolean")
        return value.configured;
    return remoteOrigin(firstString(value.origin, value.url,
        value.webuiUrl, value.webui_url)) !== "";
}

function remoteState(value) {
    var state = compactState(value);
    if (["ready", "authenticated", "online"].indexOf(state) >= 0)
        return "connected";
    if (["session-expired", "sessionexpired", "unauthorized", "sign-in-required"]
            .indexOf(state) >= 0)
        return "expired";
    if (["loading", "signing-in", "logging-in"].indexOf(state) >= 0)
        return "connecting";
    if (["failed", "failure"].indexOf(state) >= 0)
        return "error";
    if (["connected", "connecting", "disconnected", "expired", "error"]
            .indexOf(state) >= 0)
        return state;
    return "disconnected";
}

// Remote errors cross a trust boundary. Reduce them to useful known classes
// instead of reflecting arbitrary server text (which can contain URL
// credentials or the submitted password). HTTP 302 has a specific meaning in
// Hermes WebUI: the browser session is no longer signed in.
function remoteErrorMessage(value) {
    var text = string(value, "");
    if (/cross-origin redirect/i.test(text))
        return "Remote Hermes WebUI redirect was blocked";
    if (/(?:http\s*)?302|status(?:_code)?[=: ]+302|redirect(?:ed)?\s+to\s+(?:the\s+)?(?:login|sign-in)/i.test(text))
        return "Session sign-in required";
    if (/(?:http\s*)?(?:401|403)|unauthori[sz]ed|forbidden|invalid password|credential/i.test(text))
        return "Remote sign-in was rejected";
    if (/timeout|timed out/i.test(text))
        return "Remote Hermes WebUI timed out";
    if (/certificate|\btls\b|\bssl\b/i.test(text))
        return "Remote Hermes WebUI TLS failed";
    if (/refused|unreachable|host not found|name or service|network/i.test(text))
        return "Could not reach the remote Hermes WebUI";
    return text.trim() === "" ? "" : "Remote Hermes sign-in failed";
}

// This is the single backend-selection truth table for Hermes readiness. Once
// a remote URL is configured, a local provider must never be used as evidence
// that the selected remote backend is ready.
function agentBackendReady(raw) {
    var value = object(raw);
    if (value.remoteChecked !== true)
        return false;
    if (value.remoteConfigured === true)
        return remoteState(value.remoteState) === "connected"
            && value.remoteAuthenticated === true;
    return value.localProviderReady === true;
}

var exported = {
    object: object,
    array: array,
    string: string,
    firstString: firstString,
    canonicalStatus: canonicalStatus,
    normalizeConversation: normalizeConversation,
    sortedConversations: sortedConversations,
    extractText: extractText,
    normalizeMessage: normalizeMessage,
    normalizeMessages: normalizeMessages,
    applyMessageEvent: applyMessageEvent,
    normalizeTool: normalizeTool,
    applyToolEvent: applyToolEvent,
    normalizeRequest: normalizeRequest,
    normalizeQuestion: normalizeQuestion,
    applyRequestEvent: applyRequestEvent,
    eventType: eventType,
    sessionId: sessionId,
    activityLabel: activityLabel,
    counts: counts,
    relativeTime: relativeTime,
    remoteWebUrl: remoteWebUrl,
    remoteOrigin: remoteOrigin,
    remoteIsConfigured: remoteIsConfigured,
    remoteState: remoteState,
    remoteErrorMessage: remoteErrorMessage,
    agentBackendReady: agentBackendReady
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
