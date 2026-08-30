pragma Singleton
import QtQuick
import Quickshell
import "HermesHelpers.js" as Helpers
import "ExternalUrl.js" as ExternalUrl

// Public Hermes client façade used by the chip and popover. It combines the
// transport, JSON-RPC and conversation projections while keeping each lower layer
// independently testable and free of UI concerns.
Singleton {
    id: root

    readonly property string state: HermesConnection.state
    readonly property string connectionError: HermesConnection.connectionError
    readonly property bool websocketsMissing: HermesConnection.websocketsMissing
    readonly property string endpoint: HermesConnection.endpoint
    readonly property bool connected: state === "connected"

    property bool bridgeReady: false
    property string bridgeError: ""
    property string bridgeVersion: ""
    property string hermesVersion: ""
    property string backendStatus: "unknown"
    property string backendError: ""
    // Remote WebUI session state is independent from local provider setup.
    // No password is ever assigned to this singleton.
    property bool remoteChecked: false
    property bool remoteLoading: false
    property bool remoteConfigured: false
    property bool remoteAuthenticated: false
    property string remoteState: "disconnected"
    property string remoteOrigin: ""
    property string remoteError: ""
    property bool providerChecked: false
    property bool providerLoading: false
    property bool providerReady: false
    property string providerName: ""
    property string providerId: ""
    property string providerModel: ""
    property string providerError: ""
    property var capabilities: ({})
    property var remoteContract: ({})
    property var models: []
    property var commandCatalog: []

    readonly property var opts: Settings.modOpts.hermes ?? ({})
    readonly property string activityDetail: ["full", "verb", "generic"]
        .indexOf(opts.activityDetail) >= 0 ? opts.activityDetail : "verb"
    readonly property bool toastsEnabled: opts.toasts !== false

    readonly property var conversations: HermesConversations.conversations
    readonly property string selectedConversationId: HermesConversations.selectedConversationId
    readonly property var selectedConversation: HermesConversations.selectedConversation
    readonly property bool isNewChat: HermesConversations.isNewChat
    readonly property var selectedMessages: HermesConversations.selectedMessages
    readonly property var selectedTools: HermesConversations.selectedTools
    readonly property var selectedSessionState: HermesConversations.selectedSessionState
    readonly property var selectedHistory: HermesConversations.selectedHistory
    readonly property var selectedRequests: HermesConversations.selectedRequests
    readonly property string selectedError: HermesConversations.selectedError
    readonly property bool selectedLoading: HermesConversations.selectedLoading
    readonly property bool conversationsReady: HermesConversations.ready
    readonly property bool conversationsLoading: HermesConversations.loading
    readonly property string conversationsError: HermesConversations.error
    readonly property int workingCount: HermesConversations.workingCount
    readonly property int attentionCount: HermesConversations.attentionCount
    readonly property int errorCount: HermesConversations.errorCount
    readonly property int doneCount: HermesConversations.doneCount
    readonly property int unreadCount: HermesConversations.unreadCount
    readonly property var activityConversation: conversations.length > 0 ? conversations[0] : null
    readonly property string activityLabel: Helpers.activityLabel(activityConversation,
        activityDetail)
    readonly property bool remoteConnected: remoteChecked && remoteConfigured
        && remoteState === "connected" && remoteAuthenticated
    readonly property bool remoteSessionExpired: remoteChecked && remoteConfigured
        && remoteState === "expired"
    readonly property bool localProviderReady: providerChecked && providerReady
    readonly property bool localBackendAvailable:
        capabilities.localBackend === true
    readonly property bool selectedBackendReady: Helpers.agentBackendReady({
        remoteChecked: remoteChecked,
        remoteConfigured: remoteConfigured,
        remoteState: remoteState,
        remoteAuthenticated: remoteAuthenticated,
        localProviderReady: localProviderReady
    })
    readonly property bool localBackendHealthy: ["unavailable", "offline",
        "reconnecting", "error"].indexOf(backendStatus) < 0
    readonly property bool setupRequired: bridgeReady && !selectedBackendReady
    readonly property bool agentReady: connected && bridgeReady
        && selectedBackendReady
        // backendStatus describes the local Hermes gateway. A verified remote
        // WebUI session is independent from that gateway's provider health.
        && (remoteConfigured || localBackendHealthy)
    readonly property bool canOperate: agentReady
    readonly property var actionStates: HermesRpc.actionStates

    signal conversationDeleted(string conversationId)

    function actionPending(kind, conversationId, requestId) {
        return HermesRpc.actionPending(kind, conversationId, requestId);
    }

    function actionError(kind, conversationId, requestId) {
        return HermesRpc.actionError(kind, conversationId, requestId);
    }

    function actionKindPending(kind, conversationId) {
        const prefix = kind + "|" + (conversationId || "") + "|";
        for (const key in actionStates)
            if (key.indexOf(prefix) === 0 && actionStates[key]?.pending === true)
                return true;
        return false;
    }

    function openExternalUrl(value) {
        const safe = ExternalUrl.safeHttpUrl(value);
        if (safe === "")
            return false;
        Quickshell.execDetached(["xdg-open", safe]);
        return true;
    }

    function reconnect() {
        bridgeReady = false;
        bridgeError = "";
        backendError = "";
        remoteLoading = false;
        HermesConnection.reconnect();
    }

    function configureModel() {
        const home = Quickshell.env("HOME");
        Quickshell.execDetached([
            "kitty", "--title", "Hermes model setup",
            home + "/.local/bin/hermes", "model"
        ]);
    }

    function hello() {
        bridgeReady = false;
        bridgeError = "";
        HermesRpc.request("bridge.hello", {
            client: "quickshell",
            version: 1,
            capabilities: ["conversations", "streaming", "tools", "requests"]
        }, result => {
            root.applyReady(result);
            root.refreshRemoteStatus();
            root.refreshProviderStatus();
            root.loadCommandCatalog();
            HermesConversations.refreshAll();
        }, reason => {
            root.bridgeError = reason;
            root.backendStatus = "error";
        }, { timeoutMs: 15000, fallback: "Hermes bridge handshake failed" });
    }

    function applyReady(raw) {
        const value = Helpers.object(raw);
        const bridge = Helpers.object(value.bridge);
        const backend = Helpers.object(value.backend);
        bridgeVersion = Helpers.firstString(value.bridgeVersion,
            value.bridge_version, bridge.version);
        hermesVersion = Helpers.firstString(value.hermesVersion,
            value.hermes_version, backend.version, value.version);
        const connection = Helpers.firstString(value.connection,
            value.connection_state);
        backendStatus = Helpers.firstString(value.backendStatus,
            value.backend_status, connection, backend.status,
            value.status, "ready").toLowerCase();
        backendError = Helpers.firstString(value.backendError,
            value.backend_error, backend.error);
        if (backendError === "" && ["unavailable", "offline", "error"]
                .indexOf(backendStatus) >= 0)
            backendError = Helpers.firstString(value.connectionText,
                value.connection_text);
        capabilities = value.capabilities && typeof value.capabilities === "object"
            ? value.capabilities
            : value.features && typeof value.features === "object"
                ? value.features : bridge.capabilities ?? ({});
        remoteContract = value.remoteContract && typeof value.remoteContract === "object"
            ? value.remoteContract : value.remote_contract
                && typeof value.remote_contract === "object"
                ? value.remote_contract : ({});
        models = Array.isArray(value.models) ? value.models
            : Array.isArray(backend.models) ? backend.models : [];
        applyProviderStatus(value.providerStatus ?? value.provider_status
            ?? value.provider);
        const readyRemote = value.remoteStatus ?? value.remote_status ?? value.remote;
        if (readyRemote !== undefined)
            applyRemoteStatus(readyRemote);
        bridgeError = "";
        bridgeReady = true;
    }

    function applyRemoteStatus(raw) {
        const value = Helpers.object(raw);
        const statusCode = value.statusCode ?? value.status_code ?? value.code;
        const rawError = Helpers.firstString(value.error, value.message,
            value.detail, statusCode !== undefined ? String(statusCode) : "");
        let state = Helpers.remoteState(Helpers.firstString(value.state,
            value.status, value.connection, "disconnected"));
        const safeError = Helpers.remoteErrorMessage(rawError);
        if (Number(statusCode) === 302
                || safeError === "Session sign-in required")
            state = "expired";
        const reportedConfigured = Helpers.remoteIsConfigured(value);
        // While a candidate login is in flight, stay conservatively in remote
        // mode even if its failure event says that candidate was not persisted.
        // This prevents an older configured remote from briefly falling through
        // to a ready local provider before the RPC failure is delivered.
        remoteConfigured = reportedConfigured
            || HermesRpc.actionPending("remote-login", "", "");
        remoteAuthenticated = remoteConfigured && state === "connected"
            && value.authenticated === true;
        remoteChecked = true;
        remoteLoading = state === "connecting";
        remoteState = state;
        const statusOrigin = Helpers.remoteOrigin(Helpers.firstString(value.origin,
            value.url, value.webuiUrl, value.webui_url));
        // Expiry/error events may omit the URL. Keep the last safe origin so
        // the user can see which remote session needs to be renewed.
        if (statusOrigin !== "" || state === "disconnected")
            remoteOrigin = statusOrigin;
        remoteError = state === "error" ? safeError : "";
        if (state === "expired")
            remoteError = "Session sign-in required";
        else if (state === "error" && remoteError === "")
            remoteError = "Remote Hermes sign-in failed";
    }

    function applyRemoteFailure(reason) {
        const message = Helpers.remoteErrorMessage(reason);
        remoteChecked = true;
        remoteLoading = false;
        remoteAuthenticated = false;
        remoteState = message === "Session sign-in required" ? "expired" : "error";
        if (remoteState === "expired")
            remoteConfigured = true;
        remoteError = message !== "" ? message : "Remote Hermes sign-in failed";
    }

    function refreshRemoteStatus(onSuccess, onFailure) {
        if (!connected) {
            onFailure?.("Hermes bridge is offline");
            return "";
        }
        return HermesRpc.request("remote.status", {}, result => {
            root.applyRemoteStatus(result);
            if (root.remoteConnected)
                HermesConversations.refreshAll();
            onSuccess?.(result);
        }, reason => {
            root.applyRemoteFailure(reason);
            onFailure?.(root.remoteError);
        }, {
            actionKey: HermesRpc.actionKey("remote-status", "", ""),
            timeoutMs: 30000,
            fallback: "Could not check the remote Hermes session"
        });
    }

    function loginRemote(url, password, onSuccess, onFailure) {
        const safeUrl = Helpers.remoteWebUrl(url);
        if (safeUrl === "") {
            onFailure?.("Enter a valid HTTP(S) Hermes WebUI URL");
            return "";
        }
        remoteChecked = true;
        remoteLoading = true;
        remoteConfigured = true;
        remoteAuthenticated = false;
        remoteState = "connecting";
        remoteOrigin = Helpers.remoteOrigin(safeUrl);
        remoteError = "";
        // `password` is serialized directly into this one RPC frame. It is
        // never copied into a property, draft, status, callback, or log.
        return HermesRpc.request("remote.login", {
            url: safeUrl,
            password: password
        }, result => {
            root.applyRemoteStatus(result);
            if (!root.remoteConnected) {
                const reason = root.remoteError !== "" ? root.remoteError
                    : "Remote Hermes sign-in failed";
                onFailure?.(reason);
                return;
            }
            root.refreshProviderStatus();
            HermesConversations.refreshAll();
            onSuccess?.(result);
        }, reason => {
            root.applyRemoteFailure(reason);
            onFailure?.(root.remoteError);
        }, {
            actionKey: HermesRpc.actionKey("remote-login", "", ""),
            timeoutMs: 60000,
            fallback: "Remote Hermes sign-in failed"
        });
    }

    function logoutRemote(onSuccess, onFailure) {
        remoteLoading = true;
        remoteAuthenticated = false;
        remoteState = "connecting";
        remoteError = "";
        return HermesRpc.request("remote.logout", {}, result => {
            root.applyRemoteStatus(result);
            // A minimal successful logout response may contain no state.
            if (root.remoteState === "connected") {
                root.remoteState = "disconnected";
                root.remoteConfigured = false;
                root.remoteAuthenticated = false;
                root.remoteOrigin = "";
                root.remoteLoading = false;
            }
            onSuccess?.(result);
        }, reason => {
            root.applyRemoteFailure(reason);
            onFailure?.(root.remoteError);
        }, {
            actionKey: HermesRpc.actionKey("remote-logout", "", ""),
            timeoutMs: 30000,
            fallback: "Could not sign out of the remote Hermes WebUI"
        });
    }

    function applyProviderStatus(raw) {
        const value = Helpers.object(raw);
        providerChecked = value.checked === true;
        providerReady = value.ready === true;
        providerId = Helpers.firstString(value.provider, value.id);
        providerName = Helpers.firstString(value.providerName,
            value.provider_name, value.name, providerId);
        providerModel = Helpers.firstString(value.model);
        providerError = Helpers.firstString(value.error);
        providerLoading = false;
    }

    function refreshProviderStatus(onSuccess, onFailure) {
        if (!connected) {
            onFailure?.("Hermes bridge is offline");
            return "";
        }
        providerLoading = true;
        return HermesRpc.request("provider.status", { force: true }, result => {
            root.applyProviderStatus(result);
            onSuccess?.(result);
        }, reason => {
            root.providerLoading = false;
            root.providerError = reason;
            onFailure?.(reason);
        }, {
            actionKey: HermesRpc.actionKey("provider-status", "", ""),
            timeoutMs: 45000,
            fallback: "Could not check Hermes model readiness"
        });
    }

    function validateCustomProvider(url, password, onSuccess, onFailure) {
        return HermesRpc.request("provider.custom.validate", {
            url: url,
            password: password
        }, onSuccess, onFailure, {
            actionKey: HermesRpc.actionKey("provider-validate", "", ""),
            timeoutMs: 30000,
            fallback: "Could not validate the Hermes endpoint"
        });
    }

    function configureCustomProvider(url, password, model, onSuccess, onFailure) {
        return HermesRpc.request("provider.custom.configure", {
            url: url,
            password: password,
            model: model
        }, result => {
            const value = Helpers.object(result);
            root.applyProviderStatus(value.providerStatus ?? value.provider_status);
            HermesConversations.refreshAll();
            onSuccess?.(result);
        }, onFailure, {
            actionKey: HermesRpc.actionKey("provider-configure", "", ""),
            timeoutMs: 90000,
            fallback: "Could not configure the Hermes provider"
        });
    }

    function loadCommandCatalog() {
        if (!connected)
            return;
        HermesRpc.request("commands.catalog", {}, result => {
            const value = Helpers.object(result);
            root.commandCatalog = Array.isArray(result) ? result
                : Array.isArray(value.commands) ? value.commands
                    : Array.isArray(value.items) ? value.items : [];
            if (Array.isArray(value.models))
                root.models = value.models;
        }, () => {
            // Optional discovery: slash commands still dispatch when an older
            // bridge does not publish a catalog.
        }, { timeoutMs: 15000, fallback: "Hermes command catalog unavailable" });
    }

    function refresh() {
        if (!connected) {
            reconnect();
            return;
        }
        if (!bridgeReady) {
            hello();
            return;
        }
        refreshRemoteStatus();
        refreshProviderStatus();
        HermesConversations.refreshAll();
    }

    function selectConversation(conversationId) {
        return HermesConversations.selectConversation(conversationId, false);
    }

    function setPopoverVisible(value) {
        HermesConversations.panelVisible = value === true;
    }

    function draft(conversationId) {
        return HermesConversations.draft(conversationId);
    }

    function setDraft(conversationId, value) {
        HermesConversations.setDraft(conversationId, value);
    }

    function submit(conversationId, text) {
        const prompt = typeof text === "string" ? text.trim() : "";
        if (prompt === "")
            return "";
        if (conversationId === "") {
            HermesConversations.setError("", "");
            return HermesConversations.createConversation(conversation => {
                root.submit(conversation.id, prompt);
            }, reason => HermesConversations.setError("", reason));
        }
        const conversation = HermesConversations.conversationById(conversationId);
        if (!conversation || conversation.readOnly || conversation.sessionId === "")
            return "";
        if (prompt[0] === "/")
            return runCommand(conversationId, prompt);
        const key = HermesRpc.actionKey("prompt", conversationId, "");
        HermesConversations.setError(conversationId, "");
        return HermesRpc.request("prompt.submit", {
            sessionId: conversation.sessionId,
            text: prompt
        }, result => {
            HermesConversations.setDraft(conversationId, "");
            // Some bridges return the accepted user message before the event
            // stream catches up. Applying it is idempotent by message id.
            if (result && result.message)
                HermesConversations.applyEvent("message.created", Object.assign({},
                    result.message, { conversationId: conversationId,
                        sessionId: conversation.sessionId }));
        }, reason => HermesConversations.setError(conversationId, reason), {
            actionKey: key,
            timeoutMs: 30000,
            fallback: "Could not send prompt"
        });
    }

    function interrupt(conversationId) {
        const conversation = HermesConversations.conversationById(conversationId);
        if (!conversation || conversation.sessionId === "")
            return "";
        const key = HermesRpc.actionKey("interrupt", conversationId, "");
        return HermesRpc.request("session.interrupt", { sessionId: conversation.sessionId },
            () => {}, reason => HermesConversations.setError(conversationId, reason), {
                actionKey: key,
                fallback: "Could not stop Hermes"
            });
    }

    function steer(conversationId, text) {
        const conversation = HermesConversations.conversationById(conversationId);
        const prompt = typeof text === "string" ? text.trim() : "";
        if (!conversation || conversation.sessionId === "" || prompt === "")
            return "";
        const key = HermesRpc.actionKey("steer", conversationId, "");
        return HermesRpc.request("session.steer", {
            sessionId: conversation.sessionId,
            text: prompt
        }, () => HermesConversations.setDraft(conversationId, ""),
        reason => HermesConversations.setError(conversationId, reason), {
            actionKey: key,
            fallback: "Could not steer Hermes"
        });
    }

    function runCommand(conversationId, command) {
        const conversation = HermesConversations.conversationById(conversationId);
        if (!conversation || conversation.sessionId === "")
            return "";
        const body = typeof command === "string"
            ? command.trim().replace(/^\//, "") : "";
        if (body === "")
            return "";
        const splitAt = body.search(/\s/);
        const name = splitAt < 0 ? body : body.slice(0, splitAt);
        const arg = splitAt < 0 ? "" : body.slice(splitAt).trim();
        const key = HermesRpc.actionKey("command", conversationId, name);
        HermesConversations.setError(conversationId, "");
        return HermesRpc.request("slash.exec", {
            session_id: conversation.sessionId,
            command: body
        }, result => root.handleCommandResult(conversationId, body, result, key, 0),
        slashReason => {
            // Quick/plugin/skill commands live behind command.dispatch on
            // gateways where the slash worker does not recognize them.
            HermesRpc.request("command.dispatch", {
                session_id: conversation.sessionId,
                name: name,
                arg: arg
            }, result => root.handleCommandResult(conversationId, body, result, key, 0),
            dispatchReason => HermesConversations.setError(conversationId,
                /not a quick\/plugin\/skill command/i.test(dispatchReason)
                    ? slashReason : dispatchReason), {
                actionKey: key,
                timeoutMs: 60000,
                fallback: "Hermes command failed"
            });
        }, {
            actionKey: key,
            timeoutMs: 60000,
            fallback: "Hermes command failed"
        });
    }

    function unwrapCommandResult(raw) {
        const value = Helpers.object(raw);
        return value.upstream && typeof value.upstream === "object"
            ? value.upstream : value;
    }

    function renderSystemMessage(conversationId, text, failed) {
        const conversation = HermesConversations.conversationById(conversationId);
        if (!conversation || typeof text !== "string" || text.trim() === "")
            return;
        HermesConversations.applyEvent("message.created", {
            id: "system-" + conversationId + "-" + String(Date.now())
                + "-" + String(Math.floor(Math.random() * 1000)),
            conversationId: conversationId,
            sessionId: conversation.sessionId,
            role: "system",
            text: text.trim(),
            error: failed === true ? text.trim() : "",
            createdAt: new Date().toISOString()
        });
    }

    function handleCommandResult(conversationId, invocation, raw, actionKey, depth) {
        const conversation = HermesConversations.conversationById(conversationId);
        if (!conversation)
            return;
        const result = unwrapCommandResult(raw);
        const type = Helpers.firstString(result.type, result.kind).toLowerCase();
        const notice = Helpers.firstString(result.notice, result.warning);
        if (notice !== "")
            renderSystemMessage(conversationId, notice, false);
        if (type === "prefill") {
            HermesConversations.setDraft(conversationId, Helpers.firstString(result.prefill,
                result.message, result.text));
            return;
        }
        if (type === "alias") {
            if (depth >= 5) {
                HermesConversations.setError(conversationId, "Hermes command alias loop detected");
                return;
            }
            const target = Helpers.firstString(result.command, result.alias,
                result.target).replace(/^\//, "");
            if (target !== "") {
                const splitAt = invocation.search(/\s/);
                const argument = splitAt < 0 ? "" : invocation.slice(splitAt).trim();
                const aliased = target + (argument === "" ? "" : " " + argument);
                HermesRpc.request("slash.exec", {
                    session_id: conversation.sessionId,
                    command: aliased
                }, next => root.handleCommandResult(conversationId, aliased, next,
                    actionKey, depth + 1),
                reason => HermesConversations.setError(conversationId, reason), {
                    actionKey: actionKey,
                    timeoutMs: 60000,
                    fallback: "Hermes command alias failed"
                });
            }
            return;
        }
        if (type === "send" || type === "skill") {
            const message = Helpers.firstString(result.message, result.text);
            if (message === "")
                return;
            HermesRpc.request("prompt.submit", {
                sessionId: conversation.sessionId,
                text: message,
                displayText: Helpers.firstString(result.display, "/" + invocation)
            }, () => HermesConversations.setDraft(conversationId, ""),
            reason => HermesConversations.setError(conversationId, reason), {
                actionKey: actionKey,
                timeoutMs: 30000,
                fallback: "Could not send Hermes command prompt"
            });
            return;
        }
        const output = Helpers.firstString(result.output,
            type === "exec" || type === "plugin" ? result.message : "");
        if (output !== "")
            renderSystemMessage(conversationId, output, false);
        else if (notice === "")
            renderSystemMessage(conversationId, "/" + invocation + " completed", false);
        HermesConversations.setDraft(conversationId, "");
    }

    function compress(conversationId) {
        const conversation = HermesConversations.conversationById(conversationId);
        if (!conversation || conversation.sessionId === "")
            return "";
        const key = HermesRpc.actionKey("command", conversationId, "compress");
        return HermesRpc.request("session.compress", {
            session_id: conversation.sessionId
        }, raw => {
            const result = root.unwrapCommandResult(raw);
            if (Array.isArray(result.messages))
                HermesConversations.mergeHistory(conversationId, result.messages);
            const summary = Helpers.firstString(result.output, result.summary,
                "Hermes context compressed");
            root.renderSystemMessage(conversationId, summary, false);
            HermesConversations.refreshConversation(conversationId);
        }, reason => HermesConversations.setError(conversationId, reason), {
            actionKey: key,
            timeoutMs: 120000,
            fallback: "Could not compress Hermes context"
        });
    }

    function setModel(conversationId, model) {
        const conversation = HermesConversations.conversationById(conversationId);
        if (!conversation || conversation.sessionId === "" || typeof model !== "string"
                || model.trim() === "")
            return "";
        return runCommand(conversationId, "/model " + model.trim());
    }

    function startNewChat() {
        return HermesConversations.selectConversation("", false);
    }

    function deleteConversation(conversationId, onFailure) {
        return HermesConversations.deleteConversation(conversationId, () => {
            conversationDeleted(conversationId);
        }, onFailure);
    }

    function respondRequest(conversationId, request, response) {
        const conversation = HermesConversations.conversationById(conversationId);
        if (!conversation || !request)
            return "";
        const kind = Helpers.firstString(request.kind, "approval");
        const method = kind === "clarify" ? "clarify.respond"
            : kind === "sudo" ? "sudo.respond"
                : kind === "secret" ? "secret.respond" : "approval.respond";
        const key = HermesRpc.actionKey(kind, conversationId, request.id);
        const params = Object.assign({
            sessionId: conversation.sessionId,
            requestId: request.id
        }, response ?? {});
        return HermesRpc.request(method, params, () => {
            HermesConversations.applyEvent("request.resolved", {
                conversationId: conversationId,
                sessionId: conversation.sessionId,
                requestId: request.id,
                kind: kind
            });
        }, reason => HermesConversations.setError(conversationId, reason), {
            actionKey: key,
            timeoutMs: 60000,
            fallback: "Could not answer Hermes"
        });
    }

    function respondClarifyBatch(conversationId, request, answers) {
        const conversation = HermesConversations.conversationById(conversationId);
        const values = Array.isArray(answers) ? answers : [];
        if (!conversation || !request || values.length === 0)
            return "";
        const key = HermesRpc.actionKey("clarify", conversationId, request.id);
        const sendAt = index => {
            if (index >= values.length) {
                HermesConversations.applyEvent("request.resolved", {
                    conversationId: conversationId,
                    sessionId: conversation.sessionId,
                    requestId: request.id,
                    kind: "clarify"
                });
                return;
            }
            const answer = values[index];
            HermesRpc.request("clarify.respond", {
                sessionId: conversation.sessionId,
                requestId: request.id,
                questionId: answer.questionId,
                question_id: answer.questionId,
                answer: answer.answer,
                answers: Array.isArray(answer.answer) ? answer.answer : [answer.answer]
            }, () => sendAt(index + 1),
            reason => HermesConversations.setError(conversationId, reason), {
                actionKey: key,
                timeoutMs: 60000,
                fallback: "Could not answer Hermes"
            });
        };
        sendAt(0);
        return key;
    }

    function relativeTime(value) {
        return Helpers.relativeTime(value, Date.now());
    }

    Connections {
        target: HermesConnection
        function onOpened() { root.hello(); }
        function onDropped() {
            root.bridgeReady = false;
            root.backendStatus = "unknown";
            root.remoteLoading = false;
        }
    }

    Connections {
        target: HermesRpc
        function onEventReceived(type, payload) {
            const normalized = Helpers.eventType(type);
            if (normalized === "bridge-ready") {
                root.applyReady(payload);
                root.refreshRemoteStatus();
                root.refreshProviderStatus();
                root.loadCommandCatalog();
                HermesConversations.refreshAll();
            } else if (normalized === "bridge-capabilities") {
                const value = Helpers.object(payload);
                if (value.capabilities && typeof value.capabilities === "object")
                    root.capabilities = value.capabilities;
                if (value.remoteContract && typeof value.remoteContract === "object")
                    root.remoteContract = value.remoteContract;
            } else if (normalized === "bridge-connection") {
                const value = Helpers.object(payload);
                const connection = Helpers.firstString(value.connection,
                    value.state, value.status, "offline").toLowerCase();
                root.backendStatus = connection === "connected" ? "ready" : connection;
                root.backendError = ["offline", "reconnecting", "error", "unavailable"]
                    .indexOf(connection) >= 0 ? Helpers.firstString(value.error,
                        value.message, value.connectionText, value.connection_text) : "";
                if (connection === "connected")
                    HermesConversations.refreshAll();
            } else if (normalized === "provider-status") {
                root.applyProviderStatus(payload);
            } else if (normalized === "remote-status") {
                root.applyRemoteStatus(payload);
                if (root.remoteConnected)
                    HermesConversations.refreshAll();
            } else if (normalized === "remote-session-expired"
                    || normalized === "remote-expired") {
                root.remoteChecked = true;
                root.remoteLoading = false;
                root.remoteConfigured = true;
                root.remoteAuthenticated = false;
                root.remoteState = "expired";
                root.remoteError = "Session sign-in required";
            } else if (normalized === "bridge-error"
                    || normalized === "backend-error") {
                const value = Helpers.object(payload);
                root.backendError = Helpers.firstString(value.error,
                    value.message, "Hermes backend failed");
                root.backendStatus = "error";
            } else {
                HermesConversations.applyEvent(type, payload);
            }
        }
        function onProtocolError(message) { root.bridgeError = message; }
    }
}
