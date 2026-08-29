const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./shell.cjs");

const H = load("HermesHelpers.js");

test("Hermes WebUI conversations normalize history metadata and live activity", () => {
    const conversation = H.normalizeConversation({
        session_id: "session-1",
        title: "Climate history",
        model: "claude-sonnet",
        message_count: 12,
        is_streaming: true,
        activity: "Hermes is reading climate entities...",
        read_only: true,
        last_message_at: 1788004800,
    }, 0);

    assert.equal(conversation.id, "session-1");
    assert.equal(conversation.title, "Climate history");
    assert.equal(conversation.sessionId, "session-1");
    assert.equal(conversation.model, "claude-sonnet");
    assert.equal(conversation.messageCount, 12);
    assert.equal(conversation.readOnly, true);
    assert.equal(conversation.status, "working");
    assert.equal(H.activityLabel(conversation, "full"),
        "Hermes is reading climate entities...");
    assert.equal(H.activityLabel(conversation, "verb"), "reading…");
    assert.equal(H.activityLabel(conversation, "generic"), "working…");
});

test("id-less Hermes deltas accumulate under the stable id supplied by conversation state", () => {
    let messages = H.applyMessageEvent([], "message-start", {
        id: "stream-home-1", role: "assistant", text: "",
    });
    messages = H.applyMessageEvent(messages, "message-delta", {
        id: "stream-home-1", role: "assistant", text: "Hello ",
    });
    messages = H.applyMessageEvent(messages, "message-delta", {
        id: "stream-home-1", role: "assistant", text: "there",
    });
    assert.equal(messages.length, 1);
    assert.equal(messages[0].text, "Hello there");
    assert.equal(messages[0].streaming, true);

    messages = H.applyMessageEvent(messages, "message-complete", {
        id: "stream-home-1", role: "assistant", text: "Hello there!",
    });
    assert.equal(messages.length, 1);
    assert.equal(messages[0].text, "Hello there!",
        "the final snapshot replaces accumulated deltas instead of duplicating them");
    assert.equal(messages[0].streaming, false);
});

test("tool and secret request snake_case payloads retain stable protocol ids", () => {
    const tool = H.normalizeTool({
        call_id: "call-42", tool_name: "ha_get_state", status: "running",
        started_at: "2026-08-29T12:00:00Z",
    }, 0);
    assert.equal(tool.id, "call-42");
    assert.equal(tool.name, "ha_get_state");
    assert.equal(tool.terminal, false);

    const request = H.normalizeRequest({
        request_id: "secret-9", type: "secret.request", env_var: "HASS_TOKEN",
        prompt: "Home Assistant needs a token",
    }, 0);
    assert.equal(request.id, "secret-9");
    assert.equal(request.kind, "secret");
    assert.equal(request.secretName, "HASS_TOKEN");
});

test("clarification batches preserve question ids, choices, and multi-select", () => {
    const request = H.normalizeRequest({
        request_id: "clarify-1",
        kind: "clarify",
        questions: [
            {
                qid: "room",
                question: "Which room?",
                choices: ["Living room", "Office"],
            },
            {
                question_id: "entities",
                question: "Which entities?",
                choices: ["Lights", "Climate"],
                multi_select: true,
            },
        ],
    }, 0);

    assert.equal(request.questions.length, 2);
    assert.equal(request.questions[0].id, "room");
    assert.deepEqual(request.questions[0].options.map(option => option.value),
        ["Living room", "Office"]);
    assert.equal(request.questions[1].id, "entities");
    assert.equal(request.questions[1].multiSelect, true);

    const single = H.normalizeRequest({
        request_id: "clarify-2",
        kind: "clarify",
        question: "Which entities?",
        choices: ["Lights", "Climate"],
        multi_select: true,
    }, 0);
    assert.equal(single.multiSelect, true);
});

test("request expiration removes the matching blocking card", () => {
    const current = [H.normalizeRequest({ request_id: "req-1", kind: "approval" }, 0)];
    assert.deepEqual(H.applyRequestEvent(current, "request.expired",
        { request_id: "req-1" }), []);
    assert.deepEqual(H.applyRequestEvent(current, "clarify.expire",
        { request_id: "req-1" }), []);
});

test("remote Hermes WebUI URLs retain only safe HTTP origins for display", () => {
    assert.equal(H.remoteWebUrl("  https://hermes.example.com/base/  "),
        "https://hermes.example.com/base");
    assert.equal(H.remoteWebUrl("http://127.0.0.1:3000"),
        "http://127.0.0.1:3000");
    assert.equal(H.remoteOrigin("https://hermes.example.com:8443/webui/login?next=%2F"),
        "https://hermes.example.com:8443");
    assert.equal(H.remoteWebUrl("ftp://hermes.example.com"), "");
    assert.equal(H.remoteWebUrl("https://user:password@hermes.example.com"), "");
    assert.equal(H.remoteWebUrl("https://hermes.example.com/bad path"), "");
    assert.equal(H.remoteWebUrl("https:\\hermes.example.com"), "");
    assert.equal(H.remoteIsConfigured({ configured: true, url:
        "https://hermes.example.com" }), true);
    assert.equal(H.remoteIsConfigured({ configured: false, url:
        "https://failed-candidate.example.com" }), false,
        "an unselected candidate URL must not silently select remote mode");
    assert.equal(H.remoteIsConfigured({ origin:
        "https://legacy-bridge.example.com/path" }), true);
});

test("remote session states and errors are normalized without reflecting secrets", () => {
    assert.equal(H.remoteState("authenticated"), "connected");
    assert.equal(H.remoteState("session_expired"), "expired");
    assert.equal(H.remoteState("signing-in"), "connecting");
    assert.equal(H.remoteState("unexpected-upstream-state"), "disconnected");

    const secret = "do-not-reflect-this-password";
    assert.equal(H.remoteErrorMessage(`HTTP 302 redirect to /login?secret=${secret}`),
        "Session sign-in required");
    assert.equal(H.remoteErrorMessage(`401 invalid password: ${secret}`),
        "Remote sign-in was rejected");
    assert.equal(H.remoteErrorMessage("Remote Hermes attempted a cross-origin redirect"),
        "Remote Hermes WebUI redirect was blocked");
    const unknown = H.remoteErrorMessage(`upstream echoed ${secret}`);
    assert.equal(unknown, "Remote Hermes sign-in failed");
    assert.equal(unknown.includes(secret), false);
});

test("a configured remote can never inherit readiness from the local provider", () => {
    const readiness = overrides => H.agentBackendReady({
        remoteChecked: true,
        remoteConfigured: true,
        remoteState: "disconnected",
        remoteAuthenticated: false,
        localProviderReady: true,
        ...overrides,
    });

    assert.equal(readiness({ remoteChecked: false }), false,
        "readiness remains unknown until remote.status has answered");
    assert.equal(readiness({}), false,
        "a configured but disconnected remote cannot fall back to local readiness");
    assert.equal(readiness({ remoteState: "expired" }), false);
    assert.equal(readiness({ remoteState: "error" }), false);
    assert.equal(readiness({ remoteState: "connected" }), false,
        "a connected label alone is insufficient without authentication");
    assert.equal(readiness({ remoteState: "connected",
        remoteAuthenticated: true }), true);
    assert.equal(readiness({ remoteConfigured: false }), true,
        "the explicit advanced local path remains usable when no remote is selected");
    assert.equal(readiness({ remoteConfigured: false,
        localProviderReady: false }), false);
});
