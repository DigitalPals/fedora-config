const test = require("node:test");
const assert = require("node:assert/strict");

const H = require("../T3CodeHelpers.js");

const NOW = Date.parse("2026-08-03T12:00:00.000Z");

function thread(overrides = {}) {
    return {
        id: "thread-1",
        projectId: "project-1",
        title: "Thread one",
        modelSelection: { instanceId: "codex", model: "gpt-5.6-sol" },
        runtimeMode: "full-access",
        interactionMode: "default",
        branch: null,
        worktreePath: null,
        latestTurn: null,
        latestUserMessageAt: null,
        session: null,
        hasPendingApprovals: false,
        hasPendingUserInput: false,
        hasActionableProposedPlan: false,
        settledOverride: null,
        settledAt: null,
        snoozedUntil: null,
        snoozedAt: null,
        archivedAt: null,
        createdAt: "2026-08-01T12:00:00.000Z",
        updatedAt: "2026-08-03T11:00:00.000Z",
        ...overrides,
    };
}

function providers() {
    return [
        {
            instanceId: "codex",
            driver: "codex",
            displayName: "Codex",
            continuationGroupKey: "codex-main",
            showInteractionModeToggle: true,
            requiresNewThreadForModelChange: false,
            ready: true,
            models: [
                {
                    slug: "gpt-5.6-sol",
                    name: "GPT 5.6 Sol",
                    isDefault: true,
                    isCustom: false,
                    optionDescriptors: [
                        {
                            id: "effort",
                            label: "Effort",
                            type: "select",
                            options: [
                                { id: "medium", label: "Medium", isDefault: true },
                                { id: "high", label: "High" },
                            ],
                        },
                        { id: "fastMode", label: "Fast", type: "boolean", currentValue: false },
                    ],
                },
                { slug: "gpt-5.6-terra", name: "GPT 5.6 Terra", isCustom: false,
                    optionDescriptors: [] },
            ],
        },
        {
            instanceId: "codex_work",
            driver: "codex",
            displayName: "Codex Work",
            continuationGroupKey: "codex-main",
            showInteractionModeToggle: true,
            requiresNewThreadForModelChange: false,
            ready: true,
            models: [{ slug: "gpt-5.6-sol", name: "Sol", isCustom: false,
                optionDescriptors: [] }],
        },
        {
            instanceId: "claude",
            driver: "claudeAgent",
            displayName: "Claude",
            continuationGroupKey: "claude",
            showInteractionModeToggle: false,
            requiresNewThreadForModelChange: true,
            ready: true,
            models: [{
                slug: "claude-opus",
                name: "Opus",
                isDefault: true,
                isCustom: false,
                optionDescriptors: [{
                    id: "effort",
                    label: "Effort",
                    type: "select",
                    options: [
                        { id: "high", label: "High", isDefault: true },
                        { id: "ultrathink", label: "Ultrathink" },
                    ],
                    promptInjectedValues: ["ultrathink"],
                }],
            }],
        },
    ];
}

test("classification gives snooze precedence and preserves active chip counts", () => {
    const map = {
        attention: thread({ id: "attention", hasPendingUserInput: true }),
        running: thread({ id: "running", session: { status: "running" } }),
        done: thread({ id: "done", latestTurn: { state: "completed",
            requestedAt: "2026-08-03T10:00:00.000Z", completedAt: "2026-08-03T11:00:00.000Z" } }),
        snoozedAndSettled: thread({
            id: "snoozedAndSettled",
            settledOverride: "settled",
            settledAt: "2026-08-03T10:00:00.000Z",
            snoozedAt: "2026-08-03T10:30:00.000Z",
            snoozedUntil: "2026-08-04T12:00:00.000Z",
        }),
        settled: thread({ id: "settled", settledOverride: "settled",
            settledAt: "2026-08-03T10:00:00.000Z" }),
        archived: thread({ id: "archived", archivedAt: "2026-08-03T10:00:00.000Z" }),
    };
    const result = H.classifyThreads(map, { "project-1": { title: "Project" } }, NOW, 3);
    assert.deepEqual(result.active.map((value) => value.id), ["attention", "running", "done"]);
    assert.deepEqual(result.snoozed.map((value) => value.id), ["snoozedAndSettled"]);
    assert.deepEqual(result.settled.map((value) => value.id), ["settled"]);
    assert.deepEqual({ running: result.runningCount, attention: result.attentionCount,
        done: result.doneCount }, { running: 1, attention: 1, done: 1 });
});

test("running and awaiting-user threads cannot settle or snooze", () => {
    assert.equal(H.canOperateLifecycle(thread({ session: { status: "running" } }), NOW), false);
    assert.equal(H.canOperateLifecycle(thread({ hasPendingApprovals: true }), NOW), false);
    assert.equal(H.canOperateLifecycle(thread(), NOW), true);
});

test("scope metadata is backward compatible but explicit read-only is detected", () => {
    assert.deepEqual(H.normalizeScopes("", false), {
        known: false, values: [], canRead: true, canOperate: true,
    });
    const readOnly = H.normalizeScopes("orchestration:read relay:read", true);
    assert.equal(readOnly.canRead, true);
    assert.equal(readOnly.canOperate, false);
    assert.equal(H.normalizeScopes(["orchestration:read", "orchestration:operate"], true)
        .canOperate, true);
});

test("server config keeps only safe provider and capability fields", () => {
    const result = H.sanitizeServerConfig({
        environment: {
            environmentId: "env",
            label: "Laptop",
            serverVersion: "9.1.0",
            capabilities: { threadSettlement: true, threadSnooze: false,
                threadTitleRegeneration: true },
        },
        providers: [{
            instanceId: "codex",
            driver: "codex",
            enabled: true,
            installed: true,
            status: "ready",
            auth: { token: "must-not-survive" },
            models: [{ slug: "gpt", name: "GPT", isCustom: false, capabilities: {
                optionDescriptors: [{ id: "effort", label: "Effort", type: "select",
                    options: [{ id: "high", label: "High", isDefault: true }] },
                { id: "fastMode", label: "Fast", type: "boolean", currentValue: true }],
                internalSecret: "must-not-survive",
            } }],
        }],
        settings: { secret: "must-not-survive" },
    });
    assert.equal(result.providers[0].ready, true);
    assert.equal(result.capabilities.threadSettlement, true);
    assert.equal(result.serverVersion, "9.1.0");
    assert.deepEqual(result.providers[0].models[0].optionDescriptors.map((value) => value.id),
        ["effort", "fastMode"]);
    assert.equal("internalSecret" in result.providers[0].models[0], false);
    assert.equal("auth" in result.providers[0], false);
    assert.equal("settings" in result, false);
});

test("project defaults win when ready and fallback uses first ready provider default", () => {
    const ready = providers();
    const preferred = H.selectionForProject({ defaultModelSelection: {
        instanceId: "codex", model: "gpt-5.6-terra", options: [],
    } }, ready);
    assert.equal(preferred.instanceId, "codex");
    assert.equal(preferred.model, "gpt-5.6-terra");

    ready[0].ready = false;
    const fallback = H.selectionForProject({ defaultModelSelection: {
        instanceId: "missing", model: "nope",
    } }, ready);
    assert.equal(fallback.instanceId, "codex_work");
    assert.equal(fallback.model, "gpt-5.6-sol");
});

test("thread selection follows the live session and repairs unavailable persisted choices", () => {
    const ready = providers();
    const current = thread({
        modelSelection: { instanceId: "missing", model: "retired-model",
            options: [{ id: "effort", value: "high" }] },
        session: { status: "idle", providerInstanceId: "codex_work" },
    });
    assert.deepEqual(H.selectionForThread(current, ready), {
        instanceId: "codex_work",
        model: "gpt-5.6-sol",
    });

    const legacy = thread({
        modelSelection: { provider: "codex", model: "gpt-5.6-sol",
            options: [{ id: "effort", value: "high" }] },
    });
    assert.deepEqual(H.selectionForThread(legacy, ready), {
        instanceId: "codex",
        model: "gpt-5.6-sol",
        options: [{ id: "effort", value: "high" }, { id: "fastMode", value: false }],
    });
});

test("started sessions lock providers to driver and continuation group", () => {
    const current = thread({ started: true,
        session: { status: "idle", providerInstanceId: "codex_work" } });
    const allowed = H.selectableProvidersForThread(current, providers(), 0);
    assert.deepEqual(allowed.map((provider) => provider.instanceId), ["codex", "codex_work"]);
});

test("requiresNewThreadForModelChange blocks changes only after start", () => {
    const current = thread({
        started: true,
        modelSelection: { instanceId: "claude", model: "claude-opus" },
    });
    assert.equal(H.modelChangeAllowed(current,
        { instanceId: "claude", model: "another" }, providers(), 0), false);
    current.started = false;
    assert.equal(H.modelChangeAllowed(current,
        { instanceId: "claude", model: "another" }, providers(), 0), true);
});

test("traits normalize select and boolean defaults and discard invalid values", () => {
    const descriptors = providers()[0].models[0].optionDescriptors;
    const normalized = H.normalizeTraits(descriptors, [
        { id: "effort", value: "invalid" },
        { id: "fastMode", value: true },
        { id: "unknown", value: "drop" },
    ]);
    assert.deepEqual(H.traitSelections(normalized), [
        { id: "effort", value: "medium" },
        { id: "fastMode", value: true },
    ]);
});

test("Ultrathink is prompt-controlled and not dispatched as an option", () => {
    const descriptor = providers()[2].models[0].optionDescriptors;
    const normalized = H.normalizeTraits(descriptor, [{ id: "effort", value: "ultrathink" }]);
    assert.deepEqual(H.traitSelections(normalized), [{ id: "effort", value: "high" }]);
    const displayed = H.traitsForPrompt(descriptor, [{ id: "effort", value: "high" }],
        "Ultrathink:\nInvestigate this");
    assert.equal(displayed[0].currentValue, "ultrathink");
    assert.deepEqual(H.traitSelections(H.normalizeTraits(displayed,
        H.traitSelections(displayed))), [{ id: "effort", value: "high" }]);
    const applied = H.applyTraitValue(normalized, "effort", "ultrathink", "Investigate this");
    assert.equal(applied.prompt, "Ultrathink:\nInvestigate this");
    assert.deepEqual(applied.selections, [{ id: "effort", value: "high" }]);
    const blocked = H.applyTraitValue(normalized, "effort", "high",
        "Please ultrathink about this");
    assert.match(blocked.error, /Remove ultrathink/);
});

test("existing-thread command sequence persists settings before the turn", () => {
    const ids = ["meta", "runtime", "interaction", "turn"];
    const commands = H.buildExistingTurnCommands({
        currentThread: thread(),
        modelSelection: { instanceId: "codex", model: "gpt-5.6-terra",
            options: [{ id: "effort", value: "high" }] },
        runtimeMode: "approval-required",
        interactionMode: "plan",
        text: "  Follow up\n",
        messageId: "message",
        createdAt: "2026-08-03T12:00:00.000Z",
        nextId: () => ids.shift(),
    });
    assert.deepEqual(commands.map((command) => command.type), [
        "thread.meta.update",
        "thread.runtime-mode.set",
        "thread.interaction-mode.set",
        "thread.turn.start",
    ]);
    assert.equal(commands[3].message.messageId, "message");
    assert.equal(commands[3].message.text, "  Follow up\n");
    assert.deepEqual(commands[3].modelSelection.options, [{ id: "effort", value: "high" }]);
});

test("Implement here forces Default and carries the exact source plan reference", () => {
    const current = thread({ interactionMode: "plan" });
    const commands = H.buildExistingTurnCommands({
        currentThread: current,
        modelSelection: current.modelSelection,
        runtimeMode: "full-access",
        interactionMode: "default",
        text: H.buildPlanImplementationPrompt("# Plan\n\n- ship it"),
        sourceProposedPlan: { threadId: "thread-1", planId: "plan-1" },
        messageId: "message",
        createdAt: "2026-08-03T12:00:00.000Z",
        nextId: (() => { const ids = ["mode", "turn"]; return () => ids.shift(); })(),
    });
    assert.equal(commands[0].type, "thread.interaction-mode.set");
    assert.equal(commands[0].interactionMode, "default");
    assert.equal(commands[1].message.text, "PLEASE IMPLEMENT THIS PLAN:\n# Plan\n\n- ship it");
    assert.deepEqual(commands[1].sourceProposedPlan,
        { threadId: "thread-1", planId: "plan-1" });
});

test("new thread uses one atomic turn-start bootstrap in the current checkout", () => {
    const command = H.buildNewThreadCommand({
        threadId: "new-thread",
        projectId: "project-1",
        text: "  Build   the responsive client\nnow  ",
        modelSelection: { instanceId: "codex", model: "gpt-5.6-sol",
            options: [{ id: "effort", value: "medium" }] },
        runtimeMode: "full-access",
        interactionMode: "default",
        sourceProposedPlan: { threadId: "source", planId: "plan" },
        messageId: "new-message",
        createdAt: "2026-08-03T12:00:00.000Z",
        nextId: () => "new-command",
    });
    assert.deepEqual(command, {
        type: "thread.turn.start",
        commandId: "new-command",
        threadId: "new-thread",
        message: {
            messageId: "new-message",
            role: "user",
            text: "  Build   the responsive client\nnow  ",
            attachments: [],
        },
        modelSelection: { instanceId: "codex", model: "gpt-5.6-sol",
            options: [{ id: "effort", value: "medium" }] },
        titleSeed: "Build the responsive client now",
        runtimeMode: "full-access",
        interactionMode: "default",
        bootstrap: {
            createThread: {
                projectId: "project-1",
                title: "Build the responsive client now",
                modelSelection: { instanceId: "codex", model: "gpt-5.6-sol",
                    options: [{ id: "effort", value: "medium" }] },
                runtimeMode: "full-access",
                interactionMode: "default",
                branch: null,
                worktreePath: null,
                createdAt: "2026-08-03T12:00:00.000Z",
            },
        },
        sourceProposedPlan: { threadId: "source", planId: "plan" },
        createdAt: "2026-08-03T12:00:00.000Z",
    });
});

test("title generation normalizes whitespace and caps at fifty characters", () => {
    assert.equal(H.normalizedTitle("  hello\n    world  "), "hello world");
    assert.equal(H.normalizedTitle("x".repeat(70)).length, 50);
});

test("snooze presets follow local calendar boundaries", () => {
    const now = new Date(2026, 7, 3, 10, 0, 0, 0);
    const presets = H.resolveSnoozePresets(now);
    assert.deepEqual(presets.map((preset) => preset.id),
        ["hour", "evening", "tomorrow", "next-week"]);
    assert.equal(new Date(presets.find((preset) => preset.id === "tomorrow").snoozedUntil)
        .getHours(), 9);
});

test("drafts survive rejection and disconnect but clear on confirmation", () => {
    const draft = { prompt: "do not lose this", model: "gpt" };
    assert.deepEqual(H.draftAfterOutcome(draft, "accepted"), draft);
    assert.deepEqual(H.draftAfterOutcome(draft, "rejected"), draft);
    assert.deepEqual(H.draftAfterOutcome(draft, "disconnect"), draft);
    assert.equal(H.draftAfterOutcome(draft, "confirmed").prompt, "");
});

test("pending actions time out after fifteen seconds and duplicate starts are blocked", () => {
    const states = { send: { pending: true, error: "", startedAt: 1000 } };
    assert.equal(H.canBeginAction(states, "send"), false);
    assert.deepEqual(H.expireActionStates(states, 15999, 15000).expiredKeys, []);
    const expired = H.expireActionStates(states, 16000, 15000);
    assert.deepEqual(expired.expiredKeys, ["send"]);
    assert.equal(expired.states.send.pending, false);
    assert.equal(expired.states.send.error, "Action timed out");
});

test("history paginates chronologically in batches of ten", () => {
    const messages = Array.from({ length: 25 }, (_, index) => ({ id: index + 1 }));
    const first = H.historyPage(messages, 10);
    assert.deepEqual(first.items.map((message) => message.id),
        [16, 17, 18, 19, 20, 21, 22, 23, 24, 25]);
    assert.equal(first.hiddenCount, 15);
    const second = H.historyPage(messages, 20);
    assert.equal(second.items[0].id, 6);
    assert.equal(second.hasEarlier, true);
});

test("diff rendering stops at both the character and line limits", () => {
    const byLines = H.truncateDiff(Array.from({ length: 2100 }, (_, i) => `line ${i}`).join("\n"));
    assert.equal(byLines.truncated, true);
    assert.equal(byLines.text.split("\n").length, 2000);
    const byChars = H.truncateDiff("x".repeat(110000));
    assert.equal(byChars.truncated, true);
    assert.equal(byChars.text.length, 100000);
});
