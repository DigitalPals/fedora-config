// Pure helpers shared by the T3 Code QML singleton and Node tests.
// Keep this file free of Qt APIs so it remains deterministic outside QML.

var DAY_MS = 24 * 60 * 60 * 1000;
var HOUR_MS = 60 * 60 * 1000;
var QUEUED_TURN_GRACE_MS = 2 * 60 * 1000;
var MAX_PROMPT_CHARS = 120000;
var MAX_DIFF_CHARS = 100000;
var MAX_DIFF_LINES = 2000;

function parseMs(value) {
    return typeof value === "string" && value !== "" ? Date.parse(value) : NaN;
}

function firstValidTimestamp() {
    for (var i = 0; i < arguments.length; i++) {
        if (!isNaN(parseMs(arguments[i])))
            return arguments[i];
    }
    return null;
}

// Keep the elapsed clock anchored to the running turn, including the short
// period before the session adopts it. A session transition is the fallback
// when the turn projection is late or has malformed timestamps.
function resolveWorkingStartedAt(thread) {
    var turn = thread && thread.latestTurn ? thread.latestTurn : null;
    var session = thread && thread.session ? thread.session : null;
    if (turn && turn.completedAt === null)
        return firstValidTimestamp(turn.startedAt, turn.requestedAt,
            session ? session.updatedAt : null);
    return firstValidTimestamp(session ? session.updatedAt : null);
}

// Compact duration used by an inbox row, matching T3 Code's sidebar label.
function formatWorkingDurationLabel(elapsedMs) {
    var seconds = typeof elapsedMs === "number" && isFinite(elapsedMs)
        ? Math.max(0, Math.floor(elapsedMs / 1000)) : 0;
    if (seconds < 60)
        return seconds + "s";
    var minutes = Math.floor(seconds / 60);
    if (minutes < 60)
        return minutes + "m";
    return Math.floor(minutes / 60) + "h " + (minutes % 60) + "m";
}

// Conversation-tail variant keeps seconds visible until a full minute rolls
// over, as in T3 Code's live "Working for …" row.
function formatWorkingTimerLabel(elapsedMs) {
    var seconds = typeof elapsedMs === "number" && isFinite(elapsedMs)
        ? Math.max(0, Math.floor(elapsedMs / 1000)) : 0;
    if (seconds < 60)
        return seconds + "s";
    var hours = Math.floor(seconds / 3600);
    var minutes = Math.floor((seconds % 3600) / 60);
    var remainingSeconds = seconds % 60;
    if (hours > 0)
        return minutes > 0 ? hours + "h " + minutes + "m" : hours + "h";
    return remainingSeconds > 0
        ? minutes + "m " + remainingSeconds + "s" : minutes + "m";
}

function lastActivityMs(thread) {
    var turn = thread && thread.latestTurn ? thread.latestTurn : null;
    var stamps = [thread ? thread.latestUserMessageAt : null,
                  turn ? turn.requestedAt : null,
                  turn ? turn.startedAt : null,
                  turn ? turn.completedAt : null];
    var latest = NaN;
    for (var i = 0; i < stamps.length; i++) {
        var ms = parseMs(stamps[i]);
        if (!isNaN(ms) && (isNaN(latest) || ms > latest))
            latest = ms;
    }
    return latest;
}

function hasQueuedTurnStart(thread, nowMs) {
    if (!thread)
        return false;
    var messageMs = parseMs(thread.latestUserMessageAt);
    if (isNaN(messageMs))
        return false;
    if (thread.session && thread.session.status === "error")
        return false;
    if (Math.abs(nowMs - messageMs) > QUEUED_TURN_GRACE_MS)
        return false;
    var turn = thread.latestTurn;
    if (!turn)
        return true;
    var stamps = [turn.requestedAt, turn.startedAt, turn.completedAt];
    for (var i = 0; i < stamps.length; i++) {
        var ms = parseMs(stamps[i]);
        if (!isNaN(ms) && ms >= messageMs)
            return false;
    }
    return true;
}

function isEffectivelySettled(thread, nowMs, autoSettleAfterDays) {
    if (!thread || thread.hasPendingApprovals || thread.hasPendingUserInput)
        return false;
    var sessionStatus = thread.session && typeof thread.session.status === "string"
        ? thread.session.status : "";
    if (sessionStatus === "starting" || sessionStatus === "running")
        return false;
    if (hasQueuedTurnStart(thread, nowMs)) {
        var adjudicated = thread.settledOverride === "settled"
            && parseMs(thread.settledAt) >= parseMs(thread.latestUserMessageAt);
        if (!adjudicated)
            return false;
    }
    if (thread.settledOverride === "settled")
        return true;
    if (thread.settledOverride === "active")
        return false;
    if (!(autoSettleAfterDays > 0))
        return false;
    var last = lastActivityMs(thread);
    return !isNaN(last) && last < nowMs - autoSettleAfterDays * DAY_MS;
}

function isEffectivelySnoozed(thread, nowMs) {
    if (!thread)
        return false;
    var wake = parseMs(thread.snoozedUntil);
    if (isNaN(wake) || wake <= nowMs)
        return false;
    if (thread.hasPendingApprovals || thread.hasPendingUserInput)
        return false;
    var snoozedAt = parseMs(thread.snoozedAt);
    if (thread.session && thread.session.status === "error"
            && (isNaN(snoozedAt) || parseMs(thread.session.updatedAt) > snoozedAt))
        return false;
    var turn = thread.latestTurn;
    if (!isNaN(snoozedAt) && turn && turn.state === "completed"
            && parseMs(turn.completedAt) > snoozedAt)
        return false;
    return true;
}

function threadClass(thread) {
    if (thread.hasPendingApprovals || thread.hasPendingUserInput)
        return "attention";
    var sessionStatus = thread.session && typeof thread.session.status === "string"
        ? thread.session.status : "";
    var turnStatus = thread.latestTurn && typeof thread.latestTurn.state === "string"
        ? thread.latestTurn.state : "";
    if (sessionStatus === "starting" || sessionStatus === "running" || turnStatus === "running")
        return "running";
    if (sessionStatus === "error" || turnStatus === "error")
        return "error";
    if (turnStatus === "completed")
        return "done";
    return "idle";
}

function canOperateLifecycle(thread, nowMs) {
    if (!thread || thread.hasPendingApprovals || thread.hasPendingUserInput)
        return false;
    var sessionStatus = thread.session && typeof thread.session.status === "string"
        ? thread.session.status : "";
    var turnStatus = thread.latestTurn && typeof thread.latestTurn.state === "string"
        ? thread.latestTurn.state : "";
    // The dropdown deliberately keeps both settle and snooze unavailable
    // while work is live, even though the upstream server permits snoozing it.
    if (sessionStatus === "starting" || sessionStatus === "running" || turnStatus === "running")
        return false;
    return !hasQueuedTurnStart(thread, nowMs);
}

function canPrompt(thread, nowMs) {
    return canOperateLifecycle(thread, nowMs)
        && thread.hasActionableProposedPlan !== true;
}

function projectThread(thread, projectMap, nowMs, lifecycle) {
    var project = projectMap && projectMap[thread.projectId]
        ? projectMap[thread.projectId] : null;
    var cls = lifecycle === "active" ? threadClass(thread) : lifecycle;
    var modelSelection = thread.modelSelection && typeof thread.modelSelection === "object"
        ? thread.modelSelection : {};
    var sessionStatus = thread.session && typeof thread.session.status === "string"
        ? thread.session.status : "";
    return {
        id: thread.id,
        projectId: thread.projectId,
        title: typeof thread.title === "string" ? thread.title : "Untitled thread",
        project: project && typeof project.title === "string" ? project.title : "",
        cls: cls,
        lifecycle: lifecycle,
        model: typeof modelSelection.model === "string" ? modelSelection.model : "",
        modelSelection: modelSelection,
        runtimeMode: typeof thread.runtimeMode === "string" ? thread.runtimeMode : "full-access",
        interactionMode: typeof thread.interactionMode === "string"
            ? thread.interactionMode : "default",
        branch: thread.branch === null || typeof thread.branch === "string" ? thread.branch : null,
        worktreePath: thread.worktreePath === null || typeof thread.worktreePath === "string"
            ? thread.worktreePath : null,
        pendingApprovals: thread.hasPendingApprovals === true,
        pendingInput: thread.hasPendingUserInput === true,
        planReady: thread.hasActionableProposedPlan === true,
        sessionStatus: sessionStatus,
        workingStartedAt: cls === "running" ? resolveWorkingStartedAt(thread) : null,
        canPrompt: lifecycle === "active" && canPrompt(thread, nowMs),
        canLifecycle: canOperateLifecycle(thread, nowMs),
        started: thread.latestTurn !== null && thread.latestTurn !== undefined
            || thread.session !== null && thread.session !== undefined,
        settledOverride: thread.settledOverride || null,
        settledAt: thread.settledAt || null,
        snoozedUntil: thread.snoozedUntil || null,
        snoozedAt: thread.snoozedAt || null,
        titleRegeneration: thread.titleRegeneration || null,
        updatedAt: typeof thread.updatedAt === "string" ? thread.updatedAt : "",
        createdAt: typeof thread.createdAt === "string" ? thread.createdAt : ""
    };
}

function classifyThreads(threadMap, projectMap, nowMs, autoSettleAfterDays) {
    var active = [];
    var snoozed = [];
    var settled = [];
    var runningCount = 0;
    var attentionCount = 0;
    var doneCount = 0;
    var rank = { attention: 0, error: 1, running: 2, done: 3, idle: 4 };
    var source = threadMap && typeof threadMap === "object" ? threadMap : {};
    for (var id in source) {
        var thread = source[id];
        if (!thread || thread.archivedAt)
            continue;
        // Snooze is an overlay and therefore wins over settledness.
        if (isEffectivelySnoozed(thread, nowMs)) {
            snoozed.push(projectThread(thread, projectMap, nowMs, "snoozed"));
            continue;
        }
        if (isEffectivelySettled(thread, nowMs, autoSettleAfterDays)) {
            settled.push(projectThread(thread, projectMap, nowMs, "settled"));
            continue;
        }
        var projected = projectThread(thread, projectMap, nowMs, "active");
        active.push(projected);
        if (projected.cls === "running")
            runningCount++;
        else if (projected.cls === "attention" || projected.cls === "error")
            attentionCount++;
        else if (projected.cls === "done")
            doneCount++;
    }
    active.sort(function(left, right) {
        var rankDelta = rank[left.cls] - rank[right.cls];
        if (rankDelta !== 0)
            return rankDelta;
        var timeDelta = parseMs(right.updatedAt) - parseMs(left.updatedAt);
        if (!isNaN(timeDelta) && timeDelta !== 0)
            return timeDelta;
        return String(left.id).localeCompare(String(right.id));
    });
    var byRecent = function(left, right) {
        var delta = parseMs(right.updatedAt) - parseMs(left.updatedAt);
        return !isNaN(delta) && delta !== 0
            ? delta : String(left.id).localeCompare(String(right.id));
    };
    snoozed.sort(byRecent);
    settled.sort(byRecent);
    return {
        active: active,
        snoozed: snoozed,
        settled: settled,
        runningCount: runningCount,
        attentionCount: attentionCount,
        doneCount: doneCount
    };
}

function normalizeScopes(rawScope, metadataKnown) {
    var known = metadataKnown === true;
    var values = [];
    if (known && typeof rawScope === "string") {
        values = rawScope.split(/\s+/).map(function(value) { return value.trim(); })
            .filter(function(value) { return value !== ""; });
    } else if (known && Array.isArray(rawScope)) {
        values = rawScope.filter(function(value) { return typeof value === "string"; });
    }
    return {
        known: known,
        values: values,
        canRead: !known || values.indexOf("orchestration:read") >= 0,
        canOperate: !known || values.indexOf("orchestration:operate") >= 0
    };
}

function sanitizeChoice(raw) {
    if (!raw || typeof raw.id !== "string" || raw.id.trim() === ""
            || typeof raw.label !== "string" || raw.label.trim() === "")
        return null;
    return {
        id: raw.id.trim(),
        label: raw.label.trim(),
        description: typeof raw.description === "string" ? raw.description.trim() : "",
        isDefault: raw.isDefault === true
    };
}

function sanitizeDescriptor(raw) {
    if (!raw || typeof raw.id !== "string" || raw.id.trim() === ""
            || typeof raw.label !== "string" || raw.label.trim() === "")
        return null;
    if (raw.type === "boolean") {
        return {
            id: raw.id.trim(),
            label: raw.label.trim(),
            description: typeof raw.description === "string" ? raw.description.trim() : "",
            type: "boolean",
            currentValue: typeof raw.currentValue === "boolean" ? raw.currentValue : false
        };
    }
    if (raw.type !== "select" || !Array.isArray(raw.options))
        return null;
    var choices = raw.options.map(sanitizeChoice).filter(function(choice) { return choice !== null; });
    if (choices.length === 0)
        return null;
    return {
        id: raw.id.trim(),
        label: raw.label.trim(),
        description: typeof raw.description === "string" ? raw.description.trim() : "",
        type: "select",
        options: choices,
        currentValue: typeof raw.currentValue === "string" ? raw.currentValue.trim() : "",
        promptInjectedValues: Array.isArray(raw.promptInjectedValues)
            ? raw.promptInjectedValues.filter(function(value) {
                return typeof value === "string" && value.trim() !== "";
            }).map(function(value) { return value.trim(); }) : []
    };
}

function sanitizeModel(raw) {
    if (!raw || typeof raw.slug !== "string" || raw.slug.trim() === "")
        return null;
    var descriptors = raw.capabilities && Array.isArray(raw.capabilities.optionDescriptors)
        ? raw.capabilities.optionDescriptors.map(sanitizeDescriptor)
            .filter(function(value) { return value !== null; }) : [];
    return {
        slug: raw.slug.trim(),
        name: typeof raw.name === "string" && raw.name.trim() !== ""
            ? raw.name.trim() : raw.slug.trim(),
        shortName: typeof raw.shortName === "string" ? raw.shortName.trim() : "",
        isCustom: raw.isCustom === true,
        isDefault: raw.isDefault === true,
        isLegacy: raw.isLegacy === true,
        optionDescriptors: descriptors
    };
}

function sanitizeServerConfig(config) {
    var environment = config && config.environment && typeof config.environment === "object"
        ? config.environment : {};
    var rawCapabilities = environment.capabilities && typeof environment.capabilities === "object"
        ? environment.capabilities : {};
    var capabilities = {
        repositoryIdentity: rawCapabilities.repositoryIdentity === true,
        connectionProbe: rawCapabilities.connectionProbe === true,
        threadSettlement: rawCapabilities.threadSettlement === true,
        threadSnooze: rawCapabilities.threadSnooze === true,
        threadTitleRegeneration: rawCapabilities.threadTitleRegeneration === true
    };
    var providers = [];
    var rawProviders = config && Array.isArray(config.providers) ? config.providers : [];
    for (var i = 0; i < rawProviders.length; i++) {
        var raw = rawProviders[i];
        if (!raw || typeof raw.instanceId !== "string" || raw.instanceId.trim() === ""
                || typeof raw.driver !== "string" || raw.driver.trim() === "")
            continue;
        var models = Array.isArray(raw.models) ? raw.models.map(sanitizeModel)
            .filter(function(value) { return value !== null; }) : [];
        providers.push({
            instanceId: raw.instanceId.trim(),
            driver: raw.driver.trim(),
            displayName: typeof raw.displayName === "string" && raw.displayName.trim() !== ""
                ? raw.displayName.trim() : raw.instanceId.trim(),
            accentColor: typeof raw.accentColor === "string" ? raw.accentColor.trim() : "",
            continuationGroupKey: raw.continuation && typeof raw.continuation.groupKey === "string"
                ? raw.continuation.groupKey : "",
            showInteractionModeToggle: raw.showInteractionModeToggle !== false,
            requiresNewThreadForModelChange: raw.requiresNewThreadForModelChange === true,
            enabled: raw.enabled === true,
            installed: raw.installed === true,
            available: raw.availability !== "unavailable",
            status: typeof raw.status === "string" ? raw.status : "error",
            ready: raw.enabled === true && raw.availability !== "unavailable"
                && raw.status === "ready",
            message: typeof raw.message === "string" ? raw.message : "",
            models: models
        });
    }
    return {
        environmentId: typeof environment.environmentId === "string"
            ? environment.environmentId : "",
        label: typeof environment.label === "string" ? environment.label : "",
        serverVersion: typeof environment.serverVersion === "string"
            ? environment.serverVersion : "",
        capabilities: capabilities,
        providers: providers
    };
}

function findProvider(providers, instanceId) {
    var list = Array.isArray(providers) ? providers : [];
    for (var i = 0; i < list.length; i++) {
        if (list[i].instanceId === instanceId)
            return list[i];
    }
    return null;
}

function findModel(provider, slug) {
    if (!provider || !Array.isArray(provider.models))
        return null;
    for (var i = 0; i < provider.models.length; i++) {
        if (provider.models[i].slug === slug)
            return provider.models[i];
    }
    return null;
}

// Map a provider driver (or any provider-ish hint string) onto one of the
// bundled brand glyphs. Servers name drivers freely ("claudeAgent", "codex"),
// so match by family rather than exact id.
function providerIconName(hint) {
    if (typeof hint !== "string" || hint === "")
        return "";
    if (/claude|anthropic/i.test(hint))
        return "claude";
    if (/codex|openai|gpt/i.test(hint))
        return "openai";
    if (/kimi|moonshot/i.test(hint))
        return "kimi";
    return "";
}

// Resolve the glyph for a raw thread. Prefer the live session's provider,
// then the persisted selection; fall back to matching the hint strings
// directly so the glyph survives a missing provider snapshot.
function threadProviderIconName(thread, providers) {
    var persisted = thread && thread.modelSelection
        && typeof thread.modelSelection === "object" ? thread.modelSelection : {};
    var session = thread && thread.session && typeof thread.session === "object"
        ? thread.session : {};
    var hints = [
        session.providerInstanceId,
        persisted.instanceId,
        persisted.providerInstanceId,
        session.providerName,
        persisted.provider,
        persisted.driver
    ];
    for (var i = 0; i < hints.length; i++) {
        var hint = hints[i];
        if (typeof hint !== "string" || hint === "")
            continue;
        var provider = findProvider(providers, hint);
        var icon = providerIconName(provider ? provider.driver : hint);
        if (icon !== "")
            return icon;
    }
    return "";
}

// "Claude · Opus 4.5"-style summary of the provider/model a thread would
// continue with; empty while no provider snapshot is available.
function threadSelectionLabel(thread, providers) {
    var selection = selectionForThread(thread, providers);
    if (!selection)
        return "";
    var provider = findProvider(providers, selection.instanceId);
    if (!provider)
        return "";
    var model = findModel(provider, selection.model);
    var modelName = typeof selection.model === "string" ? selection.model : "";
    if (model) {
        if (typeof model.shortName === "string" && model.shortName !== "")
            modelName = model.shortName;
        else if (typeof model.name === "string" && model.name !== "")
            modelName = model.name;
    }
    return modelName !== "" ? provider.displayName + " · " + modelName
        : provider.displayName;
}

function defaultModel(provider) {
    if (!provider || !Array.isArray(provider.models) || provider.models.length === 0)
        return "";
    var i;
    for (i = 0; i < provider.models.length; i++) {
        if (provider.models[i].isDefault && !provider.models[i].isCustom)
            return provider.models[i].slug;
    }
    for (i = 0; i < provider.models.length; i++) {
        if (!provider.models[i].isCustom)
            return provider.models[i].slug;
    }
    return provider.models[0].slug;
}

function selectionObject(instanceId, model, options) {
    var result = { instanceId: instanceId, model: model };
    if (Array.isArray(options) && options.length > 0)
        result.options = options;
    return result;
}

function selectionValues(rawSelections) {
    var values = {};
    if (Array.isArray(rawSelections)) {
        for (var i = 0; i < rawSelections.length; i++) {
            var selection = rawSelections[i];
            if (selection && typeof selection.id === "string"
                    && (typeof selection.value === "string" || typeof selection.value === "boolean"))
                values[selection.id] = selection.value;
        }
    } else if (rawSelections && typeof rawSelections === "object") {
        for (var id in rawSelections) {
            if (typeof rawSelections[id] === "string" || typeof rawSelections[id] === "boolean")
                values[id] = rawSelections[id];
        }
    }
    return values;
}

function normalizeTraits(descriptors, rawSelections) {
    var values = selectionValues(rawSelections);
    var normalized = [];
    var source = Array.isArray(descriptors) ? descriptors : [];
    for (var i = 0; i < source.length; i++) {
        var descriptor = sanitizeDescriptor(source[i]);
        if (!descriptor)
            continue;
        var selected = values[descriptor.id];
        if (descriptor.type === "boolean") {
            descriptor.currentValue = typeof selected === "boolean"
                ? selected : descriptor.currentValue;
        } else {
            var advertisedCurrent = descriptor.currentValue;
            var candidate = typeof selected === "string" ? selected : descriptor.currentValue;
            var valid = descriptor.options.some(function(option) { return option.id === candidate; });
            var injected = descriptor.promptInjectedValues.indexOf(candidate) >= 0;
            if (!valid || injected) {
                var currentValid = descriptor.options.some(function(option) {
                    return option.id === advertisedCurrent;
                }) && descriptor.promptInjectedValues.indexOf(advertisedCurrent) < 0;
                var fallback = !injected && currentValid
                    ? { id: advertisedCurrent }
                    : descriptor.options.find(function(option) { return option.isDefault; });
                candidate = fallback ? fallback.id : descriptor.options[0].id;
            }
            descriptor.currentValue = candidate;
        }
        normalized.push(descriptor);
    }
    return normalized;
}

function traitSelections(descriptors) {
    var result = [];
    var source = Array.isArray(descriptors) ? descriptors : [];
    for (var i = 0; i < source.length; i++) {
        var descriptor = source[i];
        if (!descriptor || typeof descriptor.id !== "string")
            continue;
        var value = descriptor.currentValue;
        if (descriptor.type === "boolean" && typeof value === "boolean")
            result.push({ id: descriptor.id, value: value });
        else if (descriptor.type === "select" && typeof value === "string" && value !== "")
            result.push({ id: descriptor.id, value: value });
    }
    return result;
}

function isUltrathinkPrompt(prompt) {
    return typeof prompt === "string" && /\bultrathink\b/i.test(prompt);
}

// Prompt-injected values are not persisted in modelSelection.options, but the
// picker still needs to display the effective value. Upstream treats the first
// advertised select trait as the prompt-controlled effort selector.
function traitsForPrompt(descriptors, rawSelections, prompt) {
    var normalized = normalizeTraits(descriptors, rawSelections);
    if (!isUltrathinkPrompt(prompt))
        return normalized;
    for (var i = 0; i < normalized.length; i++) {
        var descriptor = normalized[i];
        if (descriptor.type !== "select")
            continue;
        if (descriptor.promptInjectedValues.indexOf("ultrathink") >= 0)
            descriptor.currentValue = "ultrathink";
        break;
    }
    return normalized;
}

function applyTraitValue(descriptors, descriptorId, rawValue, prompt) {
    var normalized = normalizeTraits(descriptors, traitSelections(descriptors));
    var at = normalized.findIndex(function(descriptor) { return descriptor.id === descriptorId; });
    if (at < 0)
        return { descriptors: normalized, selections: traitSelections(normalized), prompt: prompt, error: "Unknown trait" };
    var descriptor = normalized[at];
    var nextPrompt = typeof prompt === "string" ? prompt : "";
    if (descriptor.type === "boolean") {
        if (typeof rawValue !== "boolean")
            return { descriptors: normalized, selections: traitSelections(normalized), prompt: nextPrompt, error: "Invalid trait value" };
        descriptor.currentValue = rawValue;
    } else {
        if (typeof rawValue !== "string"
                || !descriptor.options.some(function(option) { return option.id === rawValue; }))
            return { descriptors: normalized, selections: traitSelections(normalized), prompt: nextPrompt, error: "Invalid trait value" };
        if (descriptor.promptInjectedValues.indexOf(rawValue) >= 0 && rawValue === "ultrathink") {
            var trimmed = nextPrompt.trim();
            nextPrompt = trimmed === "" ? "Ultrathink:\n"
                : /^Ultrathink:/i.test(trimmed) ? trimmed : "Ultrathink:\n" + trimmed;
            return { descriptors: normalized, selections: traitSelections(normalized), prompt: nextPrompt, error: "" };
        }
        var withoutPrefix = nextPrompt.replace(/^Ultrathink:\s*/i, "");
        if (isUltrathinkPrompt(withoutPrefix) && descriptor.promptInjectedValues.length > 0)
            return { descriptors: normalized, selections: traitSelections(normalized), prompt: nextPrompt,
                error: "Remove ultrathink from the prompt before changing this trait" };
        if (descriptor.promptInjectedValues.length > 0 && /^Ultrathink:/i.test(nextPrompt))
            nextPrompt = withoutPrefix;
        descriptor.currentValue = rawValue;
    }
    return { descriptors: normalized, selections: traitSelections(normalized), prompt: nextPrompt, error: "" };
}

function preferredEffortSelection(model, requestedEffort) {
    if (!model || !Array.isArray(model.optionDescriptors)
            || typeof requestedEffort !== "string" || requestedEffort === "")
        return null;
    var wanted = requestedEffort.toLowerCase();
    for (var i = 0; i < model.optionDescriptors.length; i++) {
        var descriptor = sanitizeDescriptor(model.optionDescriptors[i]);
        if (!descriptor || descriptor.type !== "select")
            continue;
        var id = descriptor.id.toLowerCase().replace(/[^a-z0-9]/g, "");
        var label = descriptor.label.toLowerCase().replace(/[^a-z0-9]/g, "");
        if (id !== "effort" && id !== "reasoning" && id !== "reasoningeffort"
                && label !== "effort" && label !== "reasoning"
                && label !== "reasoningeffort")
            continue;
        var option = descriptor.options.find(function(candidate) {
            return candidate.id.toLowerCase() === wanted;
        });
        if (option)
            return { id: descriptor.id, value: option.id };
    }
    return null;
}

// The menubar has one global new-thread preference, independent of per-project
// defaults. Prefer a provider that can satisfy both the requested model and
// effort; retain the project's advertised selection as a compatibility fallback.
function selectionForNewThread(project, providers, preference) {
    var fallback = selectionForProject(project, providers);
    if (!preference || typeof preference.model !== "string" || preference.model === "")
        return fallback;
    var ready = (Array.isArray(providers) ? providers : []).filter(function(provider) {
        return provider.ready === true && Array.isArray(provider.models)
            && provider.models.length > 0;
    });
    var candidates = [];
    for (var i = 0; i < ready.length; i++) {
        var model = findModel(ready[i], preference.model);
        if (model) {
            candidates.push({
                provider: ready[i],
                model: model,
                effort: preferredEffortSelection(model, preference.effort)
            });
        }
    }
    if (candidates.length === 0)
        return fallback;

    var effortCandidates = candidates.filter(function(candidate) {
        return candidate.effort !== null;
    });
    var pool = effortCandidates.length > 0 ? effortCandidates : candidates;
    var preferredInstance = typeof preference.instanceId === "string"
        ? preference.instanceId : "";
    var projectInstance = project && project.defaultModelSelection
        && typeof project.defaultModelSelection.instanceId === "string"
        ? project.defaultModelSelection.instanceId : "";
    var chosen = pool.find(function(candidate) {
        return preferredInstance !== "" && candidate.provider.instanceId === preferredInstance;
    }) || pool.find(function(candidate) {
        return projectInstance !== "" && candidate.provider.instanceId === projectInstance;
    }) || pool[0];
    var selections = chosen.effort ? [chosen.effort] : null;
    var traits = normalizeTraits(chosen.model.optionDescriptors, selections);
    return selectionObject(chosen.provider.instanceId, chosen.model.slug,
        traitSelections(traits));
}

function selectionForProject(project, providers) {
    var ready = (Array.isArray(providers) ? providers : []).filter(function(provider) {
        return provider.ready === true && Array.isArray(provider.models) && provider.models.length > 0;
    });
    var preferred = project && project.defaultModelSelection
        ? project.defaultModelSelection : null;
    if (preferred && typeof preferred.instanceId === "string" && typeof preferred.model === "string") {
        var preferredProvider = findProvider(ready, preferred.instanceId);
        var preferredModel = findModel(preferredProvider, preferred.model);
        if (preferredProvider && preferredModel) {
            var preferredTraits = normalizeTraits(preferredModel.optionDescriptors, preferred.options);
            return selectionObject(preferredProvider.instanceId, preferredModel.slug,
                traitSelections(preferredTraits));
        }
    }
    if (ready.length === 0)
        return null;
    var provider = ready[0];
    var modelSlug = defaultModel(provider);
    var model = findModel(provider, modelSlug);
    var traits = normalizeTraits(model ? model.optionDescriptors : [], null);
    return selectionObject(provider.instanceId, modelSlug, traitSelections(traits));
}

// Resolve a persisted thread selection against the latest provider snapshot.
// The live session instance wins because it is the provider that must continue
// the conversation. Older shells may only expose a driver-shaped `provider`
// field, so that is accepted as a compatibility fallback. If a configured
// model disappeared, show the provider's current default instead of leaving
// the composer in an impossible, unsendable state.
function selectionForThread(thread, providers) {
    var ready = (Array.isArray(providers) ? providers : []).filter(function(provider) {
        return provider.ready === true && Array.isArray(provider.models)
            && provider.models.length > 0;
    });
    if (ready.length === 0)
        return null;

    var persisted = thread && thread.modelSelection
        && typeof thread.modelSelection === "object" ? thread.modelSelection : {};
    var session = thread && thread.session && typeof thread.session === "object"
        ? thread.session : {};
    var instanceCandidates = [
        session.providerInstanceId,
        persisted.instanceId,
        persisted.providerInstanceId
    ];
    var provider = null;
    for (var i = 0; i < instanceCandidates.length && !provider; i++) {
        if (typeof instanceCandidates[i] === "string" && instanceCandidates[i] !== "")
            provider = findProvider(ready, instanceCandidates[i]);
    }

    if (!provider) {
        var driverCandidates = [session.providerName, persisted.provider, persisted.driver];
        for (var j = 0; j < driverCandidates.length && !provider; j++) {
            var driver = driverCandidates[j];
            if (typeof driver !== "string" || driver === "")
                continue;
            provider = ready.find(function(candidate) {
                return candidate.driver === driver || candidate.instanceId === driver;
            }) || null;
        }
    }
    if (!provider)
        provider = ready[0];

    var persistedModel = typeof persisted.model === "string" ? persisted.model : "";
    var modelSlug = findModel(provider, persistedModel)
        ? persistedModel : defaultModel(provider);
    var model = findModel(provider, modelSlug);
    var traits = normalizeTraits(model ? model.optionDescriptors : [], persisted.options);
    return selectionObject(provider.instanceId, modelSlug, traitSelections(traits));
}

function threadStarted(thread, detailMessageCount) {
    return !!thread && (thread.started === true || thread.latestTurn != null
        || thread.session != null || detailMessageCount > 0);
}

function selectableProvidersForThread(thread, providers, detailMessageCount) {
    var ready = (Array.isArray(providers) ? providers : []).filter(function(provider) {
        return provider.ready === true && provider.models.length > 0;
    });
    if (!threadStarted(thread, detailMessageCount))
        return ready;
    var currentId = thread && thread.session && typeof thread.session.providerInstanceId === "string"
        ? thread.session.providerInstanceId
        : thread && thread.modelSelection ? thread.modelSelection.instanceId : "";
    var current = findProvider(providers, currentId);
    if (!current)
        return ready;
    return ready.filter(function(provider) {
        return provider.driver === current.driver
            && (current.continuationGroupKey === ""
                || provider.continuationGroupKey === current.continuationGroupKey);
    });
}

function modelChangeAllowed(thread, nextSelection, providers, detailMessageCount) {
    if (!thread || !nextSelection)
        return false;
    var currentSelection = thread.modelSelection || {};
    var currentInstanceId = thread.session
        && typeof thread.session.providerInstanceId === "string"
        ? thread.session.providerInstanceId : currentSelection.instanceId;
    if (currentInstanceId === nextSelection.instanceId
            && currentSelection.model === nextSelection.model)
        return true;
    if (!threadStarted(thread, detailMessageCount))
        return true;
    var selectable = selectableProvidersForThread(thread, providers, detailMessageCount);
    if (!findProvider(selectable, nextSelection.instanceId))
        return false;
    var current = findProvider(providers, currentInstanceId);
    var next = findProvider(providers, nextSelection.instanceId);
    return !(current && current.requiresNewThreadForModelChange
        || next && next.requiresNewThreadForModelChange);
}

function sameSelection(left, right) {
    if (!left || !right || left.instanceId !== right.instanceId || left.model !== right.model)
        return false;
    var leftOptions = Array.isArray(left.options) ? left.options : [];
    var rightOptions = Array.isArray(right.options) ? right.options : [];
    return JSON.stringify(leftOptions) === JSON.stringify(rightOptions);
}

function normalizedTitle(prompt) {
    if (typeof prompt !== "string")
        return "";
    return prompt.replace(/\s+/g, " ").trim().slice(0, 50);
}

function buildPlanImplementationPrompt(planMarkdown) {
    return "PLEASE IMPLEMENT THIS PLAN:\n" + String(planMarkdown || "").trim();
}

function idSource(input) {
    if (input && typeof input.nextId === "function")
        return input.nextId;
    return function() { return Math.random().toString(16).slice(2); };
}

function buildExistingTurnCommands(input) {
    var nextId = idSource(input);
    var commands = [];
    var current = input.currentThread;
    var selection = input.modelSelection;
    if (!sameSelection(current.modelSelection, selection)) {
        commands.push({
            type: "thread.meta.update",
            commandId: nextId(),
            threadId: current.id,
            modelSelection: selection
        });
    }
    if (input.runtimeMode !== current.runtimeMode) {
        commands.push({
            type: "thread.runtime-mode.set",
            commandId: nextId(),
            threadId: current.id,
            runtimeMode: input.runtimeMode,
            createdAt: input.createdAt
        });
    }
    if (input.interactionMode !== current.interactionMode) {
        commands.push({
            type: "thread.interaction-mode.set",
            commandId: nextId(),
            threadId: current.id,
            interactionMode: input.interactionMode,
            createdAt: input.createdAt
        });
    }
    var turn = {
        type: "thread.turn.start",
        commandId: nextId(),
        threadId: current.id,
        message: {
            messageId: input.messageId || nextId(),
            role: "user",
            text: input.text,
            attachments: []
        },
        modelSelection: selection,
        titleSeed: current.title,
        runtimeMode: input.runtimeMode,
        interactionMode: input.interactionMode,
        createdAt: input.createdAt
    };
    if (input.sourceProposedPlan)
        turn.sourceProposedPlan = input.sourceProposedPlan;
    commands.push(turn);
    return commands;
}

function buildNewThreadCommand(input) {
    var nextId = idSource(input);
    var title = normalizedTitle(input.text);
    var createdAt = input.createdAt;
    var command = {
        type: "thread.turn.start",
        commandId: nextId(),
        threadId: input.threadId,
        message: {
            messageId: input.messageId || nextId(),
            role: "user",
            text: input.text,
            attachments: []
        },
        modelSelection: input.modelSelection,
        titleSeed: title,
        runtimeMode: input.runtimeMode,
        interactionMode: input.interactionMode,
        bootstrap: {
            createThread: {
                projectId: input.projectId,
                title: title,
                modelSelection: input.modelSelection,
                runtimeMode: input.runtimeMode,
                interactionMode: input.interactionMode,
                branch: null,
                worktreePath: null,
                createdAt: createdAt
            }
        },
        createdAt: createdAt
    };
    if (input.sourceProposedPlan)
        command.sourceProposedPlan = input.sourceProposedPlan;
    return command;
}

function resolveSnoozePresets(nowValue) {
    var now = nowValue instanceof Date ? new Date(nowValue.getTime()) : new Date(nowValue);
    var inAnHour = new Date(now.getTime() + HOUR_MS);
    var timeLabel = function(date) {
        return date.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
    };
    var presets = [{ id: "hour", label: "In 1 hour", whenLabel: timeLabel(inAnHour),
        snoozedUntil: inAnHour.toISOString() }];
    var evening = new Date(now.getTime());
    evening.setHours(18, 0, 0, 0);
    if (evening.getTime() - now.getTime() > HOUR_MS)
        presets.push({ id: "evening", label: "This evening", whenLabel: timeLabel(evening),
            snoozedUntil: evening.toISOString() });
    var tomorrow = new Date(now.getTime());
    tomorrow.setDate(tomorrow.getDate() + 1);
    tomorrow.setHours(9, 0, 0, 0);
    presets.push({ id: "tomorrow", label: "Tomorrow", whenLabel: timeLabel(tomorrow),
        snoozedUntil: tomorrow.toISOString() });
    var daysUntilMonday = (1 - now.getDay() + 7) % 7 || 7;
    var nextWeek = new Date(now.getTime());
    nextWeek.setDate(nextWeek.getDate() + daysUntilMonday);
    nextWeek.setHours(9, 0, 0, 0);
    presets.push({ id: "next-week", label: "Next week",
        whenLabel: nextWeek.toLocaleDateString(undefined, { weekday: "short" })
            + " " + timeLabel(nextWeek), snoozedUntil: nextWeek.toISOString() });
    return presets;
}

function snoozeWakeLabel(snoozedUntil, nowMs) {
    var remaining = parseMs(snoozedUntil) - nowMs;
    if (isNaN(remaining) || remaining <= 0)
        return "now";
    if (remaining < HOUR_MS)
        return Math.max(1, Math.ceil(remaining / 60000)) + "m";
    if (remaining < DAY_MS)
        return Math.ceil(remaining / HOUR_MS) + "h";
    return Math.ceil(remaining / DAY_MS) + "d";
}

function historyPage(messages, visibleCount) {
    var source = Array.isArray(messages) ? messages : [];
    var count = Math.max(10, Math.floor(visibleCount || 10));
    var start = Math.max(0, source.length - count);
    return { items: source.slice(start), hasEarlier: start > 0, hiddenCount: start };
}

function truncateDiff(rawDiff, maxChars, maxLines) {
    var source = typeof rawDiff === "string" ? rawDiff : "";
    var charLimit = typeof maxChars === "number" ? maxChars : MAX_DIFF_CHARS;
    var lineLimit = typeof maxLines === "number" ? maxLines : MAX_DIFF_LINES;
    var lines = source.split("\n");
    var lineTruncated = lines.length > lineLimit;
    var text = lineTruncated ? lines.slice(0, lineLimit).join("\n") : source;
    var charTruncated = text.length > charLimit;
    if (charTruncated)
        text = text.slice(0, charLimit);
    return {
        text: text,
        truncated: lineTruncated || charTruncated || source.length > text.length,
        totalChars: source.length,
        totalLines: lines.length
    };
}

function canBeginAction(states, key) {
    return !(states && states[key] && states[key].pending === true);
}

// Best-effort human text from an Effect RPC Failure exit. Causes serialize
// as nested tagged objects and ARRAYS (e.g. `cause: [{_tag: "Fail",
// error: {detail}}]`), so both named keys and array entries are walked.
var ERROR_TEXT_KEYS = ["message", "detail", "reason", "error", "cause", "failure", "defect"];

function findErrorText(value, depth) {
    if (depth > 6 || value === null || value === undefined)
        return "";
    if (typeof value === "string")
        return value.trim();
    if (typeof value !== "object")
        return "";
    var found;
    if (Array.isArray(value)) {
        for (var i = 0; i < value.length; i++) {
            found = findErrorText(value[i], depth + 1);
            if (found !== "" && found !== "Failure")
                return found;
        }
        return "";
    }
    for (var k = 0; k < ERROR_TEXT_KEYS.length; k++) {
        var key = ERROR_TEXT_KEYS[k];
        if (value[key] !== undefined) {
            found = findErrorText(value[key], depth + 1);
            if (found !== "" && found !== "Failure")
                return found;
        }
    }
    return "";
}

// ---- connection failures ---------------------------------------------------

// Connecting has two hops — an HTTP ticket request and the WebSocket itself —
// and a bar chip that only ever says "off" hides which one broke. These turn
// either hop into one short phrase. Qt's errorString is free-form and often
// says nothing ("", "Unknown error", "QQmlWebSocket is not ready."), and it
// prefixes handshake failures with the C++ frame that raised them; anything
// carrying no information collapses to "", which every caller reads as "keep
// the wording you had before".
var MAX_CONNECTION_ERROR_CHARS = 48;
var EMPTY_SOCKET_ERRORS = /^(unknown error|qqmlwebsocket is not ready)\.?$/i;

function shortenErrorText(text) {
    if (text.length <= MAX_CONNECTION_ERROR_CHARS)
        return text;
    var cut = text.slice(0, MAX_CONNECTION_ERROR_CHARS);
    var space = cut.lastIndexOf(" ");
    if (space > MAX_CONNECTION_ERROR_CHARS / 2)
        cut = cut.slice(0, space);
    return cut.replace(/[\s,.;:-]+$/, "") + "…";
}

function socketErrorText(raw) {
    if (typeof raw !== "string")
        return "";
    var text = raw.replace(/\s+/g, " ").trim();
    // "QWebSocketPrivate::processHandshake: Unhandled http status code: 401
    // (Unauthorized)" — the frame is noise, but it identifies the hop.
    var handshake = /processHandshake/i.test(text);
    text = text.replace(/^[A-Za-z_]\w*::[A-Za-z_]\w*:\s*/, "");
    if (text === "" || EMPTY_SOCKET_ERRORS.test(text))
        return "";
    if (/^error during ssl handshake/i.test(text)) {
        // OpenSSL states the reason last: "Error during SSL handshake:
        // error:0A00010B:SSL routines::wrong version number".
        var reason = text.split("::").pop().trim();
        return shortenErrorText(reason !== "" && !/ssl handshake/i.test(reason)
            ? "TLS handshake failed: " + reason : "TLS handshake failed");
    }
    var status = text.match(/http status code:?\s*(\d{3})/i);
    if (status !== null)
        return "WebSocket rejected (HTTP " + status[1] + ")";
    if (handshake)
        return "WebSocket handshake rejected";
    return shortenErrorText(text);
}

// The websocket-ticket POST. QML's XMLHttpRequest reports every transport
// failure — refused, DNS, TLS, timeout — as status 0 with no error text, so
// a dead host can only be reported as silence.
function ticketErrorText(status) {
    var code = typeof status === "number" && isFinite(status) ? Math.trunc(status) : 0;
    if (code <= 0)
        return "Server did not respond";
    if (code === 401 || code === 403)
        return "Pairing token rejected";
    if (code >= 500)
        return "Server error " + code;
    return "Ticket request failed (HTTP " + code + ")";
}

function expireActionStates(states, nowMs, timeoutMs) {
    var next = Object.assign({}, states || {});
    var expired = [];
    for (var key in next) {
        var value = next[key];
        // A state may carry its own budget (git actions stream for minutes
        // while the server generates a commit message or runs hooks).
        var limit = value && typeof value.timeoutMs === "number" ? value.timeoutMs : timeoutMs;
        if (value && value.pending === true && nowMs - value.startedAt >= limit) {
            next[key] = Object.assign({}, value, { pending: false, error: "Action timed out" });
            expired.push(key);
        }
    }
    return { states: next, expiredKeys: expired };
}

// ---- git actions (vcs.refreshStatus / git.runStackedAction) ----------------

var GIT_STACKED_ACTIONS = ["commit_push", "push"];

// Where git commands run for a thread: its worktree when it has one,
// otherwise the project checkout — the same fallback the server uses.
function resolveThreadCwd(thread, project) {
    if (thread && typeof thread.worktreePath === "string" && thread.worktreePath.trim() !== "")
        return thread.worktreePath;
    if (project && typeof project.workspaceRoot === "string" && project.workspaceRoot.trim() !== "")
        return project.workspaceRoot;
    return "";
}

// featureBranch is deliberately never set: the default is to commit on the
// thread's current branch (usually main) and push it. An omitted
// commitMessage makes the server generate one from the staged diff.
function buildGitActionPayload(input) {
    if (!input || typeof input !== "object")
        return null;
    var actionId = typeof input.actionId === "string" ? input.actionId.trim() : "";
    var cwd = typeof input.cwd === "string" ? input.cwd.trim() : "";
    if (actionId === "" || cwd === "" || GIT_STACKED_ACTIONS.indexOf(input.action) < 0)
        return null;
    var payload = { actionId: actionId, cwd: cwd, action: input.action };
    var message = typeof input.commitMessage === "string" ? input.commitMessage.trim() : "";
    if (message !== "")
        payload.commitMessage = message;
    return payload;
}

function sanitizeVcsStatus(raw) {
    if (!raw || typeof raw !== "object" || raw.isRepo !== true) {
        return { isRepo: false, refName: "", isDefaultRef: false,
            hasWorkingTreeChanges: false, fileCount: 0, insertions: 0, deletions: 0,
            hasPrimaryRemote: false, hasUpstream: false, aheadCount: 0, behindCount: 0,
            pr: null };
    }
    var workingTree = raw.workingTree && typeof raw.workingTree === "object"
        ? raw.workingTree : {};
    var count = function(value) {
        return typeof value === "number" && isFinite(value)
            ? Math.max(0, Math.floor(value)) : 0;
    };
    var pr = null;
    if (raw.pr && typeof raw.pr === "object"
            && typeof raw.pr.url === "string" && raw.pr.url !== "") {
        pr = {
            number: count(raw.pr.number),
            title: typeof raw.pr.title === "string" ? raw.pr.title : "",
            url: raw.pr.url,
            state: typeof raw.pr.state === "string" ? raw.pr.state : ""
        };
    }
    return {
        isRepo: true,
        refName: typeof raw.refName === "string" ? raw.refName : "",
        isDefaultRef: raw.isDefaultRef === true,
        hasWorkingTreeChanges: raw.hasWorkingTreeChanges === true,
        fileCount: Array.isArray(workingTree.files) ? workingTree.files.length : 0,
        insertions: count(workingTree.insertions),
        deletions: count(workingTree.deletions),
        hasPrimaryRemote: raw.hasPrimaryRemote === true,
        hasUpstream: raw.hasUpstream === true,
        aheadCount: count(raw.aheadCount),
        behindCount: count(raw.behindCount),
        pr: pr
    };
}

// Visibility, not enablement: an action that does not currently apply is
// hidden, matching the reference client. Push also covers publishing a
// branch that has a remote but no upstream yet.
function gitActionVisible(status, action) {
    if (!status || status.isRepo !== true)
        return false;
    if (action === "commit_push")
        return status.hasWorkingTreeChanges === true;
    if (action === "push")
        return status.hasWorkingTreeChanges !== true
            && status.hasPrimaryRemote === true
            && (status.aheadCount > 0 || status.hasUpstream !== true);
    return false;
}

// Live label for a streamed progress event; "" keeps the previous label.
function gitProgressLabel(event) {
    if (!event || typeof event !== "object")
        return "";
    if (event.kind === "phase_started" && typeof event.label === "string"
            && event.label !== "")
        return event.label;
    if (event.kind === "hook_started" && typeof event.hookName === "string"
            && event.hookName !== "")
        return "Running " + event.hookName + "…";
    return "";
}

function gitFailureMessage(event) {
    if (!event || event.kind !== "action_failed" || typeof event.message !== "string"
            || event.message === "")
        return "";
    return typeof event.phase === "string" && event.phase !== ""
        ? event.message + " (" + event.phase + ")" : event.message;
}

function gitResultSummary(result) {
    if (!result || typeof result !== "object")
        return { text: "", prUrl: "" };
    var parts = [];
    var commit = result.commit && typeof result.commit === "object" ? result.commit : {};
    var push = result.push && typeof result.push === "object" ? result.push : {};
    if (commit.status === "created") {
        var sha = typeof commit.commitSha === "string" ? commit.commitSha.slice(0, 7) : "";
        var subject = typeof commit.subject === "string" ? commit.subject : "";
        parts.push(("committed " + sha).trim() + (subject !== "" ? " · " + subject : ""));
    } else if (commit.status === "skipped_no_changes") {
        parts.push("nothing to commit");
    }
    if (push.status === "pushed") {
        parts.push(typeof push.branch === "string" && push.branch !== ""
            ? "pushed to " + push.branch : "pushed");
    } else if (push.status === "skipped_up_to_date") {
        parts.push("already up to date");
    }
    var prUrl = "";
    var pr = result.pr && typeof result.pr === "object" ? result.pr : {};
    if (typeof pr.url === "string" && pr.url !== "")
        prUrl = pr.url;
    else if (result.toast && result.toast.cta && result.toast.cta.kind === "open_pr"
            && typeof result.toast.cta.url === "string")
        prUrl = result.toast.cta.url;
    var text = parts.join(" — ");
    return {
        text: text === "" ? "Done" : text.charAt(0).toUpperCase() + text.slice(1),
        prUrl: prUrl
    };
}

function draftAfterOutcome(draft, outcome) {
    if (outcome === "confirmed")
        return Object.assign({}, draft || {}, { prompt: "" });
    return Object.assign({}, draft || {});
}

var exported = {
    DAY_MS: DAY_MS,
    HOUR_MS: HOUR_MS,
    QUEUED_TURN_GRACE_MS: QUEUED_TURN_GRACE_MS,
    MAX_PROMPT_CHARS: MAX_PROMPT_CHARS,
    MAX_DIFF_CHARS: MAX_DIFF_CHARS,
    MAX_DIFF_LINES: MAX_DIFF_LINES,
    parseMs: parseMs,
    firstValidTimestamp: firstValidTimestamp,
    resolveWorkingStartedAt: resolveWorkingStartedAt,
    formatWorkingDurationLabel: formatWorkingDurationLabel,
    formatWorkingTimerLabel: formatWorkingTimerLabel,
    lastActivityMs: lastActivityMs,
    hasQueuedTurnStart: hasQueuedTurnStart,
    isEffectivelySettled: isEffectivelySettled,
    isEffectivelySnoozed: isEffectivelySnoozed,
    threadClass: threadClass,
    canOperateLifecycle: canOperateLifecycle,
    canPrompt: canPrompt,
    classifyThreads: classifyThreads,
    normalizeScopes: normalizeScopes,
    sanitizeDescriptor: sanitizeDescriptor,
    sanitizeServerConfig: sanitizeServerConfig,
    findProvider: findProvider,
    findModel: findModel,
    defaultModel: defaultModel,
    providerIconName: providerIconName,
    threadProviderIconName: threadProviderIconName,
    threadSelectionLabel: threadSelectionLabel,
    normalizeTraits: normalizeTraits,
    traitSelections: traitSelections,
    isUltrathinkPrompt: isUltrathinkPrompt,
    traitsForPrompt: traitsForPrompt,
    applyTraitValue: applyTraitValue,
    selectionForNewThread: selectionForNewThread,
    selectionForProject: selectionForProject,
    selectionForThread: selectionForThread,
    selectableProvidersForThread: selectableProvidersForThread,
    modelChangeAllowed: modelChangeAllowed,
    sameSelection: sameSelection,
    normalizedTitle: normalizedTitle,
    buildPlanImplementationPrompt: buildPlanImplementationPrompt,
    buildExistingTurnCommands: buildExistingTurnCommands,
    buildNewThreadCommand: buildNewThreadCommand,
    resolveSnoozePresets: resolveSnoozePresets,
    snoozeWakeLabel: snoozeWakeLabel,
    historyPage: historyPage,
    truncateDiff: truncateDiff,
    canBeginAction: canBeginAction,
    findErrorText: findErrorText,
    socketErrorText: socketErrorText,
    ticketErrorText: ticketErrorText,
    expireActionStates: expireActionStates,
    draftAfterOutcome: draftAfterOutcome,
    resolveThreadCwd: resolveThreadCwd,
    buildGitActionPayload: buildGitActionPayload,
    sanitizeVcsStatus: sanitizeVcsStatus,
    gitActionVisible: gitActionVisible,
    gitProgressLabel: gitProgressLabel,
    gitFailureMessage: gitFailureMessage,
    gitResultSummary: gitResultSummary
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
