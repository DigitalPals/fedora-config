pragma Singleton
import QtQuick
import Quickshell
import "T3CodeHelpers.js" as Helpers

// T3 Code session monitor and remote control: keeps a live WebSocket
// subscription to the orchestration shell of the remote T3 Code server
// (t3.codes) and exposes project/thread state for the bar chip and
// popover, plus command T3Rpc.dispatch (approvals, prompts, settle,
// T3Rpc.interrupt) and desktop notifications on session transitions.
//
// Auth model: `scripts/t3-pair.py <pairing-url>` exchanges a one-time
// pairing code for a ~30-day bearer token stored in
// ~/.local/state/t3code-bar.json. Each (re)connect trades that token
// for a 5-minute wsTicket via HTTP, then opens wss://…/ws?wsTicket=….
Singleton {
    id: root

    // ---- connection re-exports -------------------------------------------
    // The transport lives in Common/T3Connection.qml. These stay here because
    // 274 call sites across seven files read them off T3Code, and the façade
    // is what lets that stay true while the inside is split up.
    readonly property string state: T3Connection.state
    readonly property string connectionError: T3Connection.connectionError
    readonly property bool websocketsMissing: T3Connection.websocketsMissing
    readonly property string host: T3Connection.host
    readonly property string environmentLabel: T3Connection.environmentLabel
    readonly property string environmentId: T3Connection.environmentId
    readonly property string serverVersion: T3Connection.serverVersion
    readonly property var environmentCapabilities: T3Connection.environmentCapabilities
    readonly property bool scopeMetadataKnown: T3Connection.scopeMetadataKnown
    readonly property var tokenScope: T3Connection.tokenScope

    function connect() {
        T3Connection.connect();
    }

    readonly property var scopeInfo: T3Connection.scopeInfo
    readonly property bool canRead: T3Connection.canRead
    readonly property bool canOperate: T3Connection.canOperate
    readonly property bool readOnly: T3Connection.readOnly
    readonly property bool canDispatch: T3Connection.canDispatch

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

    // Expanded-thread detail (orchestration.subscribeThread). The popover
    // owns one selection, so there is deliberately only one detail stream.
    readonly property var detailActionStates: T3Rpc.actionStates

    // Structured-input drafts live in the singleton rather than the Loader
    // delegate. A rejected response therefore survives closing the popover,
    // selecting another thread, and retrying. Only user-input.resolved removes
    // the matching draft.
    property var userInputDrafts: ({})
    property var userInputQuestionIndices: ({})

    // Composer state belongs to the process-wide singleton so Loader teardown,
    // navigation, and reconnects never discard text or selections.
    property var threadDrafts: ({})
    property var newThreadDraft: ({})
    property var pendingDraftMessages: ({})
    property string pendingNewThreadId: ""
    property string pendingNewThreadActionKey: ""
    readonly property string newThreadDefaultModel: "gpt-5.6-sol"
    readonly property string newThreadDefaultEffort: "high"

    signal newThreadConfirmed(string threadId)

    readonly property bool paired: T3Connection.paired
    readonly property string pairHint: "python3 ~/.config/quickshell/scripts/t3-pair.py '<pairing-url>'"

    // ---- rpc / action re-exports -----------------------------------------
    // Common/T3Rpc.qml owns request ids, the in-flight handler table and the
    // per-command action states. These nine are the part consumers touch.
    readonly property var actionStates: T3Rpc.actionStates

    function actionPending(kind, threadId, requestId) {
        return T3Rpc.actionPending(kind, threadId, requestId);
    }

    function actionError(kind, threadId, requestId) {
        return T3Rpc.actionError(kind, threadId, requestId);
    }

    function respondApproval(threadId, requestId, decision) {
        T3Rpc.respondApproval(threadId, requestId, decision);
    }

    function respondUserInput(threadId, requestId, answers) {
        T3Rpc.respondUserInput(threadId, requestId, answers);
    }

    function settle(threadId) {
        T3Rpc.settle(threadId);
    }

    function unsettle(threadId) {
        T3Rpc.unsettle(threadId);
    }

    function snooze(threadId, snoozedUntil) {
        T3Rpc.snooze(threadId, snoozedUntil);
    }

    function unsnooze(threadId) {
        T3Rpc.unsnooze(threadId);
    }

    function stopSession(threadId) {
        T3Rpc.stopSession(threadId);
    }

    // Stacked git actions stream progress while the server generates a
    // commit message and runs hooks; the deadline slides on each chunk.
    readonly property int gitActionTimeoutMs: 120000
    readonly property int maxPromptChars: Helpers.MAX_PROMPT_CHARS

    // ---- thread re-exports -----------------------------------------------
    // Common/T3Threads.qml owns the maps, the classification and the
    // projections. These are what the chip and the inbox read.
    readonly property var threads: T3Threads.threads
    readonly property var snoozedThreads: T3Threads.snoozedThreads
    readonly property var settledThreads: T3Threads.settledThreads
    readonly property int runningCount: T3Threads.runningCount
    readonly property int attentionCount: T3Threads.attentionCount
    readonly property int doneCount: T3Threads.doneCount
    readonly property bool shellReady: T3Threads.shellReady
    readonly property bool hasProjects: T3Threads.hasProjects

    function projectedThread(threadId) {
        return T3Threads.projectedThread(threadId);
    }

    function threadUrl(threadId) {
        return T3Threads.threadUrl(threadId);
    }

    function relTime(iso) {
        return T3Threads.relTime(iso);
    }

    function workingTimerLabel(iso) {
        return T3Threads.workingTimerLabel(iso);
    }

    function sortedProjects() {
        return T3Threads.sortedProjects();
    }

    function snoozePresets() {
        return T3Threads.snoozePresets();
    }

    function snoozeWakeLabel(iso) {
        return T3Threads.snoozeWakeLabel(iso);
    }

    function historyPage(messages, visibleCount) {
        return T3Threads.historyPage(messages, visibleCount);
    }

    // ---- protocol --------------------------------------------------------

    function loadServerConfig() {
        configLoading = true;
        configReady = false;
        configError = "";
        T3Rpc.requestOnce("server.getConfig", {}, value => {
            if (!value || typeof value !== "object") {
                root.configLoading = false;
                root.configError = "Malformed server configuration";
                return;
            }
            const safe = Helpers.sanitizeServerConfig(value);
            root.providerConfigurations = safe.providers;
            // The environment fields belong to the connection: the descriptor
            // fetch fills them first and this refines them, so both writers
            // have to target the same properties.
            T3Connection.environmentCapabilities = safe.capabilities;
            if (safe.environmentId !== "")
                T3Connection.environmentId = safe.environmentId;
            if (safe.label !== "")
                T3Connection.environmentLabel = safe.label;
            if (safe.serverVersion !== "")
                T3Connection.serverVersion = safe.serverVersion;
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
        const selected = T3Detail.detailThreadId;
        T3Rpc.clearRpcHandlers();
        T3Rpc.nextReqId = 2;
        T3Threads.threadMap = {};
        T3Threads.projectMap = {};
        T3Threads.shellReady = false;
        T3Detail.detailReqId = "";
        T3Detail.resetDetailData();
        T3Threads.nowMs = Date.now();
        T3Threads.rebuild();
        configReady = false;
        loadServerConfig();
        if (canRead)
            T3Rpc.sendRequest(T3Rpc.shellReqId, "orchestration.subscribeShell", {});
        else
            T3Threads.shellReady = false;
        // A reconnect invalidates every stream request id. Keep the user's
        // selection and establish a fresh detail stream on the new socket.
        if (selected !== "") {
            T3Detail.pendingDetailResubscribeId = selected;
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
                T3Connection.send(JSON.stringify({ _tag: "Ack", requestId: msg.requestId }));
                if (reqId === T3Rpc.shellReqId) {
                    for (const item of (Array.isArray(msg.values) ? msg.values : []))
                        dirty = T3Threads.applyItem(item) || dirty;
                } else if (T3Rpc.rpcHandlers[reqId]) {
                    for (const item of (Array.isArray(msg.values) ? msg.values : []))
                        T3Rpc.rpcHandlers[reqId].item?.(item);
                }
            } else if (msg._tag === "Exit") {
                if (reqId === T3Rpc.shellReqId) {
                    // Stream ended server-side (shutdown/restart): reconnect.
                    scheduleRetry();
                } else if (T3Rpc.rpcHandlers[reqId]) {
                    T3Rpc.rpcHandlers[reqId].exit?.(msg);
                    T3Rpc.dropRpcHandler(reqId);
                }
            }
        }
        if (dirty)
            T3Threads.rebuild();
    }

// ---- composer drafts and provider selection --------------------------

    function providerConfiguration(instanceId) {
        return Helpers.findProvider(providerConfigurations, instanceId);
    }

    function providerIcon(instanceId) {
        const provider = providerConfiguration(instanceId);
        return Helpers.providerIconName(provider ? provider.driver : instanceId);
    }

    function threadProviderIcon(threadId) {
        return Helpers.threadProviderIconName(T3Threads.rawThread(threadId), providerConfigurations);
    }

    function threadSelectionLabel(threadId) {
        return Helpers.threadSelectionLabel(T3Threads.rawThread(threadId), providerConfigurations);
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

    function defaultNewThreadSelection(project) {
        return Helpers.selectionForNewThread(project, providerConfigurations, {
            model: newThreadDefaultModel,
            effort: newThreadDefaultEffort
        });
    }

    function reconcileDraftSelections() {
        let draftsChanged = false;
        const drafts = Object.assign({}, threadDrafts);
        for (const threadId in drafts) {
            const draft = drafts[threadId];
            let selection = selectionFromDraft(draft);
            if (!selection)
                selection = Helpers.selectionForThread(T3Threads.threadMap[threadId], providerConfigurations);
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
                newSelection = defaultNewThreadSelection(T3Threads.projectMap[newThreadDraft.projectId]);
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
        const thread = T3Threads.threadMap[threadId];
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
        const thread = T3Threads.threadMap[threadId];
        const allowed = Helpers.selectableProvidersForThread(thread, providerConfigurations,
            T3Detail.detailThreadId === threadId ? T3Detail.detailMessages.length : 0);
        const provider = Helpers.findProvider(allowed, instanceId);
        if (!provider)
            return;
        const model = Helpers.defaultModel(provider);
        if (!Helpers.modelChangeAllowed(thread, { instanceId: instanceId, model: model },
                providerConfigurations, T3Detail.detailThreadId === threadId ? T3Detail.detailMessages.length : 0)) {
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
        const thread = T3Threads.threadMap[threadId];
        const draft = threadDraft(threadId);
        const provider = providerConfiguration(draft.instanceId);
        const config = Helpers.findModel(provider, model);
        if (!config)
            return;
        const nextSelection = { instanceId: draft.instanceId, model: model };
        if (!Helpers.modelChangeAllowed(thread, nextSelection, providerConfigurations,
                T3Detail.detailThreadId === threadId ? T3Detail.detailMessages.length : 0)) {
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
        const thread = T3Threads.threadMap[threadId];
        const detailCount = T3Detail.detailThreadId === threadId ? T3Detail.detailMessages.length : 0;
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
        return provider.models.filter(model => Helpers.modelChangeAllowed(T3Threads.threadMap[threadId],
            { instanceId: provider.instanceId, model: model.slug }, providerConfigurations,
            T3Detail.detailThreadId === threadId ? T3Detail.detailMessages.length : 0));
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
        const context = T3Threads.threadMap[contextThreadId];
        if (context && T3Threads.projectMap[context.projectId])
            return context.projectId;
        const projects = T3Threads.sortedProjects();
        return projects.length > 0 ? projects[0].id : "";
    }

    function buildNewDraft(projectId, prompt, sourceProposedPlan, projectFixed, modeFixed) {
        const project = T3Threads.projectMap[projectId];
        const selection = defaultNewThreadSelection(project);
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
        if (newThreadDraft.projectFixed === true || !T3Threads.projectMap[projectId])
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
        const source = T3Threads.threadMap[sourceThreadId];
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
        const thread = T3Threads.threadMap[threadId];
        const draft = threadDraft(threadId);
        const key = T3Rpc.actionKey("prompt", threadId, "");
        const text = typeof overrideText === "string" ? overrideText : draft.prompt;
        if (!thread || text.trim() === "")
            return T3Rpc.rejectAction(key, "Write a message first", false);
        if (text.length > maxPromptChars)
            return T3Rpc.rejectAction(key, "Prompt exceeds T3 Code's 120,000 character limit", false);
        if (!Helpers.canOperateLifecycle(thread, Date.now()))
            return T3Rpc.rejectAction(key, "Wait for the thread to become idle", false);
        const interactionMode = interactionOverride ?? draft.interactionMode;
        if (!sourceProposedPlan && thread.hasActionableProposedPlan === true
                && interactionMode !== "plan")
            return T3Rpc.rejectAction(key, "Choose a plan action before continuing", false);
        const selection = selectionFromDraft(draft);
        if (!selection)
            return T3Rpc.rejectAction(key, "Choose a ready provider and model", false);
        if (!Helpers.modelChangeAllowed(thread, selection, providerConfigurations,
                T3Detail.detailThreadId === threadId ? T3Detail.detailMessages.length : 0))
            return T3Rpc.rejectAction(key, "Start a new thread to change this model", false);
        const createdAt = new Date().toISOString();
        const messageId = T3Rpc.genId();
        const commands = Helpers.buildExistingTurnCommands({
            currentThread: thread,
            modelSelection: selection,
            runtimeMode: draft.runtimeMode,
            interactionMode: interactionMode,
            text: text,
            messageId: messageId,
            sourceProposedPlan: sourceProposedPlan ?? null,
            createdAt: createdAt,
            nextId: () => T3Rpc.genId()
        });
        putPendingDraftMessage(threadId, { messageId: messageId, prompt: text,
            clearDraft: clearDraft !== false });
        return T3Rpc.dispatchBatch(commands, key, {
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
        const key = T3Rpc.actionKey("new", "", "");
        const text = draft && typeof draft.prompt === "string" ? draft.prompt : "";
        if (!hasReadyProvider)
            return T3Rpc.rejectAction(key, configReady ? "No provider with an advertised model is ready"
                : "Provider configuration is not ready", false);
        if (!draft || !T3Threads.projectMap[draft.projectId])
            return T3Rpc.rejectAction(key, "Choose a project", false);
        if (text.trim() === "")
            return T3Rpc.rejectAction(key, "Write the first prompt", false);
        if (text.length > maxPromptChars)
            return T3Rpc.rejectAction(key, "Prompt exceeds T3 Code's 120,000 character limit", false);
        const selection = selectionFromDraft(draft);
        if (!selection)
            return T3Rpc.rejectAction(key, "Choose a ready provider and model", false);
        const threadId = T3Rpc.genId();
        const createdAt = new Date().toISOString();
        const command = Helpers.buildNewThreadCommand({
            threadId: threadId,
            projectId: draft.projectId,
            text: text,
            modelSelection: selection,
            runtimeMode: draft.runtimeMode,
            interactionMode: draft.modeFixed === true ? "default" : draft.interactionMode,
            sourceProposedPlan: draft.sourceProposedPlan,
            messageId: T3Rpc.genId(),
            createdAt: createdAt,
            nextId: () => T3Rpc.genId()
        });
        pendingNewThreadId = threadId;
        pendingNewThreadActionKey = key;
        const dispatched = T3Rpc.dispatchBatch([command], key, {
            holdAfterSuccess: true,
            onSuccess: () => {
                const current = T3Rpc.actionStates[key];
                if (current)
                    T3Rpc.putActionState(key, Object.assign({}, current, {
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
        if (!T3Threads.threadMap[pendingNewThreadId])
            return;
        const confirmed = pendingNewThreadId;
        if (pendingNewThreadActionKey !== "")
            T3Rpc.clearAction(pendingNewThreadActionKey);
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

    // ---- detail re-exports -------------------------------------------------
    // Common/T3Detail.qml owns the open thread's stream and its projections.
    // Only T3ThreadPage reads these.
    readonly property bool detailLoading: T3Detail.detailLoading
    readonly property string detailError: T3Detail.detailError
    readonly property var detailMessages: T3Detail.detailMessages
    readonly property var detailSession: T3Detail.detailSession
    readonly property var detailApprovals: T3Detail.detailApprovals
    readonly property var detailPendingInputs: T3Detail.detailPendingInputs
    readonly property var detailLatestActivity: T3Detail.detailLatestActivity
    readonly property var detailActionablePlan: T3Detail.detailActionablePlan
    readonly property var detailCheckpointSummary: T3Detail.detailCheckpointSummary
    readonly property var detailDiff: T3Detail.detailDiff
    readonly property var detailVcs: T3Detail.detailVcs
    readonly property var detailGit: T3Detail.detailGit

    function openDetail(threadId) {
        T3Detail.openDetail(threadId);
    }

    function closeDetail() {
        T3Detail.closeDetail();
    }

    function loadFullThreadDiff(threadId, checkpoint) {
        T3Detail.loadFullThreadDiff(threadId, checkpoint);
    }

    // ---- git actions -----------------------------------------------------

    function threadCwd(threadId) {
        const thread = T3Threads.threadMap[threadId];
        return Helpers.resolveThreadCwd(thread, thread ? T3Threads.projectMap[thread.projectId] : null);
    }

    // Reads T3Detail.detailVcs so QML visibility bindings refresh with the status.
    function gitActionApplies(action) {
        return Helpers.gitActionVisible(T3Detail.detailVcs.status, action);
    }

    function refreshVcsStatus(threadId, force) {
        if (state !== "connected" || !canRead || T3Detail.detailThreadId !== threadId)
            return;
        if (force !== true && T3Detail.detailVcs.fetchedAt > 0
                && Date.now() - T3Detail.detailVcs.fetchedAt < 10000)
            return;
        const cwd = threadCwd(threadId);
        if (cwd === "") {
            // No worktree and no project root: nothing to show, hide the card.
            T3Detail.detailVcs = ({ cwd: "", loading: false, error: "", status: null,
                fetchedAt: Date.now() });
            return;
        }
        T3Detail.detailVcs = Object.assign({}, T3Detail.detailVcs, { cwd: cwd, loading: true, error: "" });
        T3Rpc.requestOnce("vcs.refreshStatus", { cwd: cwd }, value => {
            if (T3Detail.detailThreadId !== threadId)
                return;
            T3Detail.detailVcs = ({ cwd: cwd, loading: false, error: "",
                status: Helpers.sanitizeVcsStatus(value), fetchedAt: Date.now() });
        }, error => {
            if (T3Detail.detailThreadId !== threadId)
                return;
            T3Detail.detailVcs = Object.assign({}, T3Detail.detailVcs, {
                loading: false, error: error, fetchedAt: Date.now()
            });
        }, { fallback: "Repository status unavailable" });
    }

    // action: "commit_push" (commit on the current branch + push — the
    // default flow) or "push". The commit message is generated server-side.
    function runGitAction(threadId, action) {
        const key = T3Rpc.actionKey("git", threadId, "");
        if (!Helpers.canBeginAction(T3Rpc.actionStates, key))
            return "";
        if (!canOperate)
            return T3Rpc.rejectAction(key, "This pairing is read-only", false);
        if (state !== "connected")
            return T3Rpc.rejectAction(key, "Not connected", false);
        const payload = Helpers.buildGitActionPayload({
            actionId: T3Rpc.genId(), cwd: threadCwd(threadId), action: action });
        if (!payload)
            return T3Rpc.rejectAction(key, "No repository folder for this thread", false);
        T3Rpc.beginAction(key, "", false, gitActionTimeoutMs);
        T3Detail.detailGit = ({ actionId: payload.actionId, action: action,
            label: action === "push" ? "Pushing…" : "Committing…",
            summary: "", prUrl: "", error: "" });
        // The terminal chunk (action_finished/action_failed) is what
        // T3Rpc.requestOnce retains; a Failure exit prefers the streamed message.
        let streamedFailure = "";
        const finish = fields => {
            if (T3Detail.detailThreadId === threadId
                    && T3Detail.detailGit.actionId === payload.actionId)
                T3Detail.detailGit = Object.assign({ actionId: "", action: "", label: "",
                    summary: "", prUrl: "", error: "" }, fields);
            root.refreshVcsStatus(threadId, true);
        };
        return T3Rpc.requestOnce("git.runStackedAction", payload, value => {
            T3Rpc.clearAction(key);
            const failure = streamedFailure !== "" ? streamedFailure
                : value && value.kind === "action_finished" ? "" : "Git action failed";
            if (failure !== "") {
                finish({ error: failure });
                return;
            }
            const summary = Helpers.gitResultSummary(value.result);
            finish({ summary: summary.text, prUrl: summary.prUrl });
        }, error => {
            const message = streamedFailure !== "" ? streamedFailure : error;
            T3Rpc.failAction(key, message);
            finish({ error: message });
        }, {
            actionKey: key,
            timeoutMs: gitActionTimeoutMs,
            slidingDeadline: true,
            fallback: "Git action failed",
            onItem: event => {
                const failure = Helpers.gitFailureMessage(event);
                if (failure !== "")
                    streamedFailure = failure;
                // Keep the expiry sweep fed while progress is flowing.
                const current = T3Rpc.actionStates[key];
                if (current && current.pending === true)
                    T3Rpc.putActionState(key, Object.assign({}, current,
                        { startedAt: Date.now() }));
                if (T3Detail.detailThreadId !== threadId
                        || T3Detail.detailGit.actionId !== payload.actionId)
                    return;
                const label = Helpers.gitProgressLabel(event);
                if (label !== "")
                    T3Detail.detailGit = Object.assign({}, T3Detail.detailGit, { label: label });
            }
        });
        // Deliberately not interrupted on detail close/switch: interrupting
        // could abort a server-side push mid-flight. Late results are no-ops
        // behind the T3Detail.detailThreadId/actionId guards above.
    }

    // The transport's half of the conversation. T3Connection owns the socket;
    // this is where its frames become protocol.
    Connections {
        target: T3Detail

        function onDraftMessageConfirmed(threadId, messageId) {
            root.confirmDraftMessage(threadId, messageId);
        }

        function onUserInputResolved(threadId, requestId) {
            root.clearUserInputDraft(threadId, requestId);
        }

        function onVcsRefreshWanted(threadId) {
            root.refreshVcsStatus(threadId, true);
        }
    }

    Connections {
        target: T3Threads

        // A snapshot replaced the world: draft selections may point at threads
        // or projects that no longer exist.
        function onSnapshotApplied() {
            root.reconcileDraftSelections();
            root.reconcileNewThreadCreation();
        }

        function onThreadUpserted(threadId) {
            root.reconcileNewThreadCreation(threadId);
        }

        // Shell updates carry a fresher session summary than the detail stream
        // while that stream is catching up.
        function onRebuilt() {
            T3Detail.adoptShellSummary(T3Threads.threadMap[T3Detail.detailThreadId]);
        }
    }

    Connections {
        target: T3Rpc

        // The RPC layer dropped everything in flight; the detail subscription
        // id it was holding is meaningless now.
        function onAborted() {
            T3Detail.detailReqId = "";
        }
    }

    Connections {
        target: T3Connection

        function onMessage(text) {
            root.handleMessage(text);
        }

        function onOpened() {
            root.subscribe();
        }

        // Fired before a retry is armed: nothing in flight can still land.
        function onDropped() {
            T3Rpc.abortPendingRpcs();
            T3Rpc.failAllPendingActions("Disconnected before confirmation");
            root.configLoading = false;
            root.configReady = false;
        }
    }
}
