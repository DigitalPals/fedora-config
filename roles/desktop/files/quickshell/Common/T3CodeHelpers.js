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

function expireActionStates(states, nowMs, timeoutMs) {
    var next = Object.assign({}, states || {});
    var expired = [];
    for (var key in next) {
        var value = next[key];
        if (value && value.pending === true && nowMs - value.startedAt >= timeoutMs) {
            next[key] = Object.assign({}, value, { pending: false, error: "Action timed out" });
            expired.push(key);
        }
    }
    return { states: next, expiredKeys: expired };
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
    normalizeTraits: normalizeTraits,
    traitSelections: traitSelections,
    isUltrathinkPrompt: isUltrathinkPrompt,
    traitsForPrompt: traitsForPrompt,
    applyTraitValue: applyTraitValue,
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
    expireActionStates: expireActionStates,
    draftAfterOutcome: draftAfterOutcome
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
