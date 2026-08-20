const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./shell.cjs");

const H = load("T3CodeHelpers.js");

const NOW = Date.parse("2026-08-03T12:00:00.000Z");

test("Markdown links carry an explicit readable color in the rich document", () => {
    const markdown = "at [`storage.rs`](t3://file/storage.rs#L283), see "
        + "[build-template.sh](https://example.test/build-template.sh?a=1&b=2) "
        + "and ![preview](https://example.test/image.png)";
    const styled = H.styleMarkdownLinks(markdown, "#b9c3ff");

    assert.match(styled,
        /<a href="t3:\/\/file\/storage\.rs#L283"><font color="#b9c3ff"><tt>storage\.rs<\/tt><\/font><\/a>/);
    assert.match(styled,
        /href="https:\/\/example\.test\/build-template\.sh\?a=1&amp;b=2"/);
    assert.match(styled, /<font color="#b9c3ff">build-template\.sh<\/font>/);
    assert.match(styled, /!\[preview\]\(https:\/\/example\.test\/image\.png\)/,
        "images must remain Markdown images rather than becoming text links");
    assert.equal(H.styleMarkdownLinks("[file](https://example.test)", "blue"),
        "<a href=\"https://example.test\"><font color=\"#ffffff\">file</font></a>");
});

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
        backgroundLiveness: null,
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

test("a pin beats settledness, loses to snooze, and still feeds the chip counts", () => {
    const map = {
        pinnedQuiet: thread({ id: "pinnedQuiet", pinnedAt: "2026-08-02T12:00:00.000Z",
            settledOverride: "settled", settledAt: "2026-08-03T10:00:00.000Z" }),
        pinnedBusy: thread({ id: "pinnedBusy", pinnedAt: "2026-08-02T12:00:00.000Z",
            hasPendingUserInput: true }),
        pinnedSnoozed: thread({ id: "pinnedSnoozed", pinnedAt: "2026-08-02T12:00:00.000Z",
            snoozedAt: "2026-08-03T10:30:00.000Z",
            snoozedUntil: "2026-08-04T12:00:00.000Z" }),
        plain: thread({ id: "plain", session: { status: "running" } }),
    };
    const result = H.classifyThreads(map, { "project-1": { title: "Project" } }, NOW, 3);
    assert.deepEqual(result.pinned.map((value) => value.id).sort(),
        ["pinnedBusy", "pinnedQuiet"]);
    assert.deepEqual(result.active.map((value) => value.id), ["plain"]);
    assert.deepEqual(result.snoozed.map((value) => value.id), ["pinnedSnoozed"]);
    assert.deepEqual(result.settled, []);
    // pinnedBusy needs attention even though it sits in the pinned section.
    assert.deepEqual({ running: result.runningCount, attention: result.attentionCount },
        { running: 1, attention: 1 });
    const busy = result.pinned.find((value) => value.id === "pinnedBusy");
    assert.equal(busy.pinned, true);
    assert.equal(busy.pinnedAt, "2026-08-02T12:00:00.000Z");
    assert.equal(busy.cls, "attention");
});

test("pinned order: orderKey ascending first, then keyless pins newest-created", () => {
    const map = {
        keyless_old: thread({ id: "keyless_old", pinnedAt: "2026-08-02T12:00:00.000Z",
            createdAt: "2026-07-01T12:00:00.000Z" }),
        keyless_new: thread({ id: "keyless_new", pinnedAt: "2026-08-02T12:00:00.000Z",
            createdAt: "2026-08-01T12:00:00.000Z" }),
        key_b: thread({ id: "key_b", pinnedAt: "2026-08-02T12:00:00.000Z",
            pinOrderKey: "b" }),
        key_a: thread({ id: "key_a", pinnedAt: "2026-08-02T12:00:00.000Z",
            pinOrderKey: "a" }),
    };
    const result = H.classifyThreads(map, {}, NOW, 3);
    assert.deepEqual(result.pinned.map((value) => value.id),
        ["key_a", "key_b", "keyless_new", "keyless_old"]);
});

test("working time follows the live turn and falls back through valid timestamps", () => {
    const startedAt = "2026-08-03T11:42:00.000Z";
    const requestedAt = "2026-08-03T11:41:00.000Z";
    const sessionAt = "2026-08-03T11:40:00.000Z";
    assert.equal(H.resolveWorkingStartedAt(thread({
        latestTurn: { state: "running", startedAt, requestedAt, completedAt: null },
        session: { status: "running", updatedAt: sessionAt },
    })), startedAt);
    assert.equal(H.resolveWorkingStartedAt(thread({
        latestTurn: { state: "running", startedAt: "invalid", requestedAt,
            completedAt: null },
        session: { status: "running", updatedAt: sessionAt },
    })), requestedAt);
    assert.equal(H.resolveWorkingStartedAt(thread({
        latestTurn: { state: "completed", startedAt, completedAt: "2026-08-03T11:59:00.000Z" },
        session: { status: "running", updatedAt: sessionAt },
    })), sessionAt);

    const projected = H.classifyThreads({ running: thread({
        id: "running",
        latestTurn: { state: "running", startedAt, requestedAt, completedAt: null },
        session: { status: "running", updatedAt: sessionAt },
    }) }, {}, NOW, 3).active[0];
    assert.equal(projected.workingStartedAt, startedAt);
});

test("working duration labels match inbox and conversation precision", () => {
    assert.equal(H.formatWorkingDurationLabel(59_999), "59s");
    assert.equal(H.formatWorkingDurationLabel(60_000), "1m");
    assert.equal(H.formatWorkingDurationLabel(65 * 60_000), "1h 5m");
    assert.equal(H.formatWorkingTimerLabel(90_000), "1m 30s");
    assert.equal(H.formatWorkingTimerLabel(60 * 60_000), "1h");
    assert.equal(H.formatWorkingTimerLabel(-1_000), "0s");
});

test("live agent count ignores background jobs and follows tolerant task transitions", () => {
    const event = (kind, taskId, payload = {}) => ({
        kind, createdAt: "2026-08-03T11:00:00.000Z",
        payload: { taskId, ...payload },
    });
    const activities = [
        event("task.started", "shell", { agentKind: "background", taskType: "local_bash" }),
        event("task.started", "one", { agentKind: "agent", taskType: "local_agent" }),
        event("task.started", "two", { agentKind: "agent", taskType: "local_agent" }),
        event("task.started", "three", { agentKind: "agent", taskType: "local_agent" }),
        event("task.started", "four", { agentKind: "agent", taskType: "local_agent" }),
        event("task.started", "five", { agentKind: "agent", taskType: "local_agent" }),
    ];
    assert.equal(H.liveAgentCount(activities, true), 5);

    const transitions = activities.concat([
        // Later rows inherit the original membership marker.
        event("task.completed", "one", { status: "completed" }),
        event("task.updated", "two", { status: "waiting" }),
        event("task.progress", "three", { status: "idle" }),
        // A duplicate/late start cannot reopen a terminal task.
        event("task.started", "one", { agentKind: "agent" }),
    ]);
    assert.equal(H.liveAgentCount(transitions, true), 3);
    assert.equal(H.liveAgentCount(transitions.concat([
        // Explicit status changes do reactivate reusable identities.
        event("task.updated", "one", { status: "running" }),
    ]), true), 4);
    assert.equal(H.liveAgentCount(activities, false), 0);
});

test("background liveness outranks a completed turn but not a session failure", () => {
    const completedTurn = { state: "completed", requestedAt: "2026-08-03T10:00:00.000Z",
        startedAt: "2026-08-03T10:00:00.000Z",
        completedAt: "2026-08-03T11:00:00.000Z" };
    const map = {
        working: thread({ id: "working", latestTurn: completedTurn,
            session: { status: "ready", updatedAt: "2026-08-03T11:00:00.000Z" },
            backgroundLiveness: "working" }),
        monitoring: thread({ id: "monitoring", latestTurn: completedTurn,
            session: { status: "ready", updatedAt: "2026-08-03T11:00:00.000Z" },
            backgroundLiveness: "monitoring" }),
        failed: thread({ id: "failed", latestTurn: completedTurn,
            session: { status: "error", updatedAt: "2026-08-03T11:00:00.000Z" },
            backgroundLiveness: "working" }),
    };
    const result = H.classifyThreads(map, {}, NOW, 3);
    assert.deepEqual(result.active.map((value) => [value.id, value.cls]), [
        ["failed", "error"], ["working", "running"], ["monitoring", "monitoring"],
    ]);
    assert.deepEqual({ running: result.runningCount, monitoring: result.monitoringCount,
        attention: result.attentionCount, done: result.doneCount },
        { running: 1, monitoring: 1, attention: 1, done: 0 });
    assert.equal(result.active.find((value) => value.id === "working").backgroundLiveness,
        "working");
    assert.equal(result.active.find((value) => value.id === "working").foregroundWorking,
        false);
    // Background work outlives the foreground turn, so the upstream client
    // still permits another prompt or an explicit lifecycle action here.
    assert.equal(H.canOperateLifecycle(map.working, NOW), true);
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
                threadPinning: true, threadPinReorder: false,
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
    assert.equal(result.capabilities.threadPinning, true);
    assert.equal(result.capabilities.threadPinReorder, false);
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

test("new threads prefer GPT-5.6 Sol with high effort across project defaults", () => {
    const ready = providers();
    const preferred = H.selectionForNewThread({ defaultModelSelection: {
        instanceId: "codex", model: "gpt-5.6-terra", options: [],
    } }, ready, { model: "gpt-5.6-sol", effort: "high" });
    assert.deepEqual(preferred, {
        instanceId: "codex",
        model: "gpt-5.6-sol",
        options: [
            { id: "effort", value: "high" },
            { id: "fastMode", value: false },
        ],
    });

    const compatible = H.selectionForNewThread({ defaultModelSelection: {
        instanceId: "codex_work", model: "gpt-5.6-sol", options: [],
    } }, ready, { model: "gpt-5.6-sol", effort: "high" });
    assert.equal(compatible.instanceId, "codex");
    assert.deepEqual(compatible.options.find((option) => option.id === "effort"),
        { id: "effort", value: "high" });

    const fallback = H.selectionForNewThread({ defaultModelSelection: {
        instanceId: "codex", model: "gpt-5.6-terra", options: [],
    } }, ready, { model: "unavailable", effort: "high" });
    assert.equal(fallback.model, "gpt-5.6-terra");
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

test("a per-state timeout outlives the default budget but still expires", () => {
    const states = {
        git: { pending: true, error: "", startedAt: 1000, timeoutMs: 120000 },
        send: { pending: true, error: "", startedAt: 1000 },
    };
    const atDefault = H.expireActionStates(states, 16000, 15000);
    assert.deepEqual(atDefault.expiredKeys, ["send"]);
    assert.equal(atDefault.states.git.pending, true);
    const atOwnLimit = H.expireActionStates(states, 121000, 15000);
    assert.ok(atOwnLimit.expiredKeys.includes("git"));
    assert.equal(atOwnLimit.states.git.error, "Action timed out");
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

test("provider glyphs resolve by driver family, not exact id", () => {
    assert.equal(H.providerIconName("claudeAgent"), "claude");
    assert.equal(H.providerIconName("codex"), "openai");
    assert.equal(H.providerIconName("kimi-cli"), "kimi");
    assert.equal(H.providerIconName("mystery"), "");
    assert.equal(H.providerIconName(""), "");
    assert.equal(H.providerIconName(null), "");
});

test("thread glyph prefers the live session and survives a missing provider snapshot", () => {
    const list = providers();
    const claude = thread({
        modelSelection: { instanceId: "claude", model: "opus" },
        session: { providerInstanceId: "codex", status: "running" },
    });
    assert.equal(H.threadProviderIconName(claude, list), "openai");
    const persistedOnly = thread({ modelSelection: { instanceId: "claude", model: "opus" } });
    assert.equal(H.threadProviderIconName(persistedOnly, list), "claude");
    const noSnapshot = thread({ modelSelection: { provider: "claudeAgent", model: "opus" } });
    assert.equal(H.threadProviderIconName(noSnapshot, []), "claude");
    assert.equal(H.threadProviderIconName(thread({ modelSelection: null }), list), "");
});

test("thread selection label pairs provider display name with the model", () => {
    assert.equal(H.threadSelectionLabel(thread(), providers()), "Codex · GPT 5.6 Sol");
    assert.equal(H.threadSelectionLabel(thread(), []), "");
});

test("diff rendering stops at both the character and line limits", () => {
    const byLines = H.truncateDiff(Array.from({ length: 2100 }, (_, i) => `line ${i}`).join("\n"));
    assert.equal(byLines.truncated, true);
    assert.equal(byLines.text.split("\n").length, 2000);
    const byChars = H.truncateDiff("x".repeat(110000));
    assert.equal(byChars.truncated, true);
    assert.equal(byChars.text.length, 100000);
});

test("thread cwd prefers the worktree and falls back to the project root", () => {
    const project = { id: "project-1", workspaceRoot: "/home/u/code/app" };
    assert.equal(H.resolveThreadCwd(thread({ worktreePath: "/tmp/wt" }), project), "/tmp/wt");
    assert.equal(H.resolveThreadCwd(thread(), project), "/home/u/code/app");
    assert.equal(H.resolveThreadCwd(thread(), null), "");
    assert.equal(H.resolveThreadCwd(null, { workspaceRoot: "  " }), "");
});

test("git payloads default to the current branch and omit empty messages", () => {
    const payload = H.buildGitActionPayload({
        actionId: "a1", cwd: "/repo", action: "commit_push", commitMessage: "  " });
    assert.deepEqual(payload, { actionId: "a1", cwd: "/repo", action: "commit_push" });
    assert.equal("featureBranch" in payload, false);
    const withMessage = H.buildGitActionPayload({
        actionId: "a1", cwd: "/repo", action: "push", commitMessage: " fix bar " });
    assert.equal(withMessage.commitMessage, "fix bar");
    assert.equal(H.buildGitActionPayload({ actionId: "a1", cwd: "/repo",
        action: "commit_push_pr" }), null);
    assert.equal(H.buildGitActionPayload({ actionId: "", cwd: "/repo",
        action: "push" }), null);
    assert.equal(H.buildGitActionPayload({ actionId: "a1", cwd: "",
        action: "push" }), null);
});

function vcsStatus(overrides = {}) {
    return {
        isRepo: true,
        hasPrimaryRemote: true,
        isDefaultRef: true,
        refName: "main",
        hasWorkingTreeChanges: true,
        workingTree: {
            files: [
                { path: "a.ts", insertions: 10, deletions: 2 },
                { path: "b.ts", insertions: 5, deletions: 1 },
            ],
            insertions: 15,
            deletions: 3,
        },
        hasUpstream: true,
        aheadCount: 2,
        behindCount: 0,
        pr: null,
        ...overrides,
    };
}

test("vcs status sanitizing keeps counts, drops malformed input, and needs a PR url", () => {
    const clean = H.sanitizeVcsStatus(vcsStatus({
        pr: { number: 42, title: "Fix", url: "https://github.com/o/r/pull/42", state: "open" },
    }));
    assert.equal(clean.refName, "main");
    assert.equal(clean.fileCount, 2);
    assert.equal(clean.insertions, 15);
    assert.equal(clean.aheadCount, 2);
    assert.equal(clean.pr.url, "https://github.com/o/r/pull/42");
    assert.equal(H.sanitizeVcsStatus(vcsStatus({ pr: { number: 1, url: "" } })).pr, null);
    assert.equal(H.sanitizeVcsStatus(null).isRepo, false);
    assert.equal(H.sanitizeVcsStatus({ isRepo: false }).fileCount, 0);
    const partial = H.sanitizeVcsStatus({ isRepo: true, refName: null, aheadCount: "3" });
    assert.equal(partial.refName, "");
    assert.equal(partial.aheadCount, 0);
});

test("git actions are only visible when they actually apply", () => {
    const status = H.sanitizeVcsStatus(vcsStatus());
    assert.equal(H.gitActionVisible(status, "commit_push"), true);
    assert.equal(H.gitActionVisible(status, "push"), false);
    const cleanTree = H.sanitizeVcsStatus(vcsStatus({ hasWorkingTreeChanges: false,
        workingTree: { files: [], insertions: 0, deletions: 0 } }));
    assert.equal(H.gitActionVisible(cleanTree, "commit_push"), false);
    assert.equal(H.gitActionVisible(cleanTree, "push"), true);
    const current = H.sanitizeVcsStatus(vcsStatus({ hasWorkingTreeChanges: false,
        aheadCount: 0 }));
    assert.equal(H.gitActionVisible(current, "push"), false);
    const unpublished = H.sanitizeVcsStatus(vcsStatus({ hasWorkingTreeChanges: false,
        workingTree: { files: [], insertions: 0, deletions: 0 }, aheadCount: 0,
        hasUpstream: false }));
    assert.equal(H.gitActionVisible(unpublished, "push"), true);
    const noRemote = H.sanitizeVcsStatus(vcsStatus({ hasPrimaryRemote: false,
        hasUpstream: false, aheadCount: 0 }));
    assert.equal(H.gitActionVisible(noRemote, "push"), false);
    assert.equal(H.gitActionVisible(H.sanitizeVcsStatus(null), "commit_push"), false);
    assert.equal(H.gitActionVisible(status, "create_pr"), false);
});

test("git progress labels follow phases and hooks, other chunks keep the label", () => {
    assert.equal(H.gitProgressLabel({ kind: "phase_started", phase: "commit",
        label: "Generating commit message..." }), "Generating commit message...");
    assert.equal(H.gitProgressLabel({ kind: "hook_started", hookName: "pre-commit" }),
        "Running pre-commit…");
    assert.equal(H.gitProgressLabel({ kind: "hook_output", text: "noise" }), "");
    assert.equal(H.gitProgressLabel({ kind: "action_started", phases: ["commit"] }), "");
    assert.equal(H.gitProgressLabel(null), "");
});

test("streamed failures carry the phase and non-failures are ignored", () => {
    assert.equal(H.gitFailureMessage({ kind: "action_failed", phase: "push",
        message: "remote rejected" }), "remote rejected (push)");
    assert.equal(H.gitFailureMessage({ kind: "action_failed", phase: null,
        message: "boom" }), "boom");
    assert.equal(H.gitFailureMessage({ kind: "action_finished" }), "");
    assert.equal(H.gitFailureMessage(null), "");
});

test("git result summaries compress the steps and surface the PR url", () => {
    const full = H.gitResultSummary({
        action: "commit_push",
        branch: { status: "skipped_not_requested" },
        commit: { status: "created", commitSha: "abc1234def", subject: "Fix the bar" },
        push: { status: "pushed", branch: "main" },
        pr: { status: "skipped_not_requested" },
        toast: { title: "Done", cta: { kind: "none" } },
    });
    assert.equal(full.text, "Committed abc1234 · Fix the bar — pushed to main");
    assert.equal(full.prUrl, "");
    const skipped = H.gitResultSummary({
        commit: { status: "skipped_no_changes" },
        push: { status: "skipped_up_to_date" },
        pr: { status: "skipped_not_requested" },
    });
    assert.equal(skipped.text, "Nothing to commit — already up to date");
    const fromPr = H.gitResultSummary({
        commit: { status: "skipped_not_requested" },
        push: { status: "pushed", branch: "feat/x" },
        pr: { status: "created", url: "https://github.com/o/r/pull/7" },
    });
    assert.equal(fromPr.prUrl, "https://github.com/o/r/pull/7");
    const fromToast = H.gitResultSummary({
        commit: { status: "skipped_not_requested" },
        push: { status: "skipped_not_requested" },
        pr: { status: "opened_existing" },
        toast: { title: "PR", cta: { kind: "open_pr", label: "View PR",
            url: "https://github.com/o/r/pull/8" } },
    });
    assert.equal(fromToast.prUrl, "https://github.com/o/r/pull/8");
    assert.equal(H.gitResultSummary(null).text, "");
});

test("error text is extracted from array-shaped Effect causes", () => {
    // Exact Exit shape captured live from git.runStackedAction on thebeast.
    const exit = {
        _tag: "Failure",
        cause: [{ _tag: "Fail", error: { _tag: "GitCommandError",
            operation: "GitVcsDriver.pushCurrentBranch", command: "git",
            cwd: "/tmp/x",
            detail: "Cannot push because no git remote is configured for this repository." } }],
    };
    assert.equal(H.findErrorText(exit, 0),
        "Cannot push because no git remote is configured for this repository.");
    assert.equal(H.findErrorText({ _tag: "Failure",
        cause: [{ _tag: "Die", defect: "worker crashed" }] }, 0), "worker crashed");
    assert.equal(H.findErrorText({ _tag: "Failure", cause: [] }, 0), "");
    assert.equal(H.findErrorText(null, 0), "");
});

// Every string below was captured from a Qt 6.11 QML WebSocket / XMLHttpRequest
// against a refused port, an unresolvable host, a plaintext server addressed as
// wss:, and a server that answers the upgrade with 401.
test("socket error text keeps what a user can act on and drops Qt's noise", () => {
    assert.equal(H.socketErrorText("Connection refused"), "Connection refused");
    assert.equal(H.socketErrorText("Host not found"), "Host not found");
    assert.equal(H.socketErrorText("The remote host closed the connection"),
        "The remote host closed the connection");
    assert.equal(H.socketErrorText(
        "Error during SSL handshake: error:0A00010B:SSL routines::wrong version number"),
        "TLS handshake failed: wrong version number");
    assert.equal(H.socketErrorText("Error during SSL handshake"), "TLS handshake failed");
    assert.equal(H.socketErrorText("QWebSocketPrivate::processHandshake: "
        + "Unhandled http status code: 401 (Unauthorized)"),
        "WebSocket rejected (HTTP 401)");
    assert.equal(H.socketErrorText("QWebSocketPrivate::processHandshake: "
        + "Unsupported WWW-Authenticate challenges encountered."),
        "WebSocket handshake rejected");
});

test("a socket error with nothing to say reads as no error at all", () => {
    // A closed status arrives with an empty string; callers must not let that
    // overwrite the error that explains the disconnect.
    assert.equal(H.socketErrorText(""), "");
    assert.equal(H.socketErrorText("   \n  "), "");
    assert.equal(H.socketErrorText("Unknown error"), "");
    assert.equal(H.socketErrorText("unknown error."), "");
    assert.equal(H.socketErrorText("QQmlWebSocket is not ready."), "");
    assert.equal(H.socketErrorText(null), "");
    assert.equal(H.socketErrorText(undefined), "");
    assert.equal(H.socketErrorText(42), "");
});

test("a long socket error is shortened to fit a bar tooltip", () => {
    const long = H.socketErrorText("The proxy refused the connection because the "
        + "upstream certificate could not be verified");
    assert.equal(long, "The proxy refused the connection because the…");
    assert.ok(long.length <= 49);
    assert.equal(H.socketErrorText("Multi\nline   error\ttext"), "Multi line error text");
});

test("ticket request failures name the hop that broke", () => {
    // QML's XMLHttpRequest collapses refused/DNS/TLS/timeout into status 0.
    assert.equal(H.ticketErrorText(0), "Server did not respond");
    assert.equal(H.ticketErrorText(undefined), "Server did not respond");
    assert.equal(H.ticketErrorText(NaN), "Server did not respond");
    assert.equal(H.ticketErrorText(502), "Server error 502");
    assert.equal(H.ticketErrorText(401), "Pairing token rejected");
    assert.equal(H.ticketErrorText(404), "Ticket request failed (HTTP 404)");
});
