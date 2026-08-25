const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir, load } = require("./shell.cjs");

function read(relative) {
    return fs.readFileSync(path.join(shellDir, relative), "utf8");
}

test("the GitHub singleton publishes the persistent Inbox contract", () => {
    const source = read("Common/GitHub.qml");
    for (const property of ["inboxItems", "inboxReady", "inboxPolling",
        "inboxCheckedAt", "inboxError", "pendingInboxCount", "settledInboxCount",
        "unreadInboxCount", "unreadRepoCount", "workflowRepoErrors", "eventRepoErrors",
        "ciReportsEnabled"])
        assert.match(source, new RegExp(`property[^\n]*\\b${property}:`), property);
    for (const action of ["settleInboxItem", "unsettleInboxItem"])
        assert.match(source, new RegExp(`function ${action}\\(key\\)`));
    assert.match(source, /function settleAllInboxItems\(\)/);
    assert.match(source,
        /property string seenAt:[\s\S]*property string activitySeenAt:[\s\S]*property var lastPush:[\s\S]*property var runBaselines:[\s\S]*property var inboxItems:[\s\S]*property var inboxSourceRevisions:/,
        "Inbox state must append to every legacy state field");
    assert.match(source, /stateData\.inboxItems = Helpers\.compactInboxItems\(root\.inboxState\)/);
    assert.match(source, /stateData\.inboxSourceRevisions = root\.inboxSourceRevisions/);
    assert.match(source, /badgeVisible:[^\n]*pendingInboxCount > 0/);
    assert.doesNotMatch(source, /unreadRepoCount\s*\+/,
        "view-based repository dots must not enter the bar badge count");
    const markSeen = source.match(/function markSeen\(\)[\s\S]*?\n    \}/)?.[0] ?? "";
    assert.match(markSeen, /activitySeenAt = stamp/);
    assert.doesNotMatch(markSeen, /setInboxSettlement|settleInboxItem/,
        "closing the popover only clears emphasis");
});

test("full Inbox and active-workflow sweeps use independent fixed cadences", () => {
    const source = read("Common/GitHub.qml");
    const full = source.match(/Timer \{\s*id: inboxTimer[\s\S]*?\n    \}/)?.[0] ?? "";
    const active = source.match(/Timer \{\s*id: activeInboxTimer[\s\S]*?\n    \}/)?.[0] ?? "";
    assert.match(full, /interval:\s*60000/);
    assert.match(full, /running:\s*root\.pollEnabled/);
    assert.match(full, /root\.refreshInbox\(false\)/);
    assert.match(active, /interval:\s*30000/);
    assert.match(active,
        /running:\s*root\.pollEnabled && root\.ciReportsEnabled && root\.runningCount > 0/);
    assert.match(active, /root\.refreshActiveInbox\(\)/);

    const sweep = source.match(/function startInboxSweep[\s\S]*?\n    \}/)?.[0] ?? "";
    assert.match(sweep, /if \(ciReportsEnabled\)[\s\S]*kind: "runs"/);
    assert.match(sweep, /if \(full\)[\s\S]*kind: "events"[\s\S]*kind: "notifications"/,
        "events and notifications must still poll with workflow reports disabled");
    assert.match(source, /queue = queue\.filter\(job => job\.interactive\)/,
        "turning the module off discards queued background reads");
});

test("repository events use conditional HTTP polling and preserve partial caches", () => {
    const source = read("Common/GitHub.qml");
    const pump = source.match(/function pump\(\)[\s\S]*?\n    \}/)?.[0] ?? "";
    assert.match(pump, /job\.kind === "events"[\s\S]*command\.push\("--include"\)/);
    assert.match(pump, /If-None-Match:/);
    assert.match(source, /eventPollDue\(slug, now\)/);
    assert.match(source, /response\.pollIntervalMs/);
    assert.match(source,
        /const notModified = job\.kind === "events"[\s\S]*included\.notModified[\s\S]*HTTP 304/);
    assert.match(source, /if \(notModified\)[\s\S]*patchEventResult\(job\.slug, null, ""\)/,
        "304 is successful even though it has no jq body");
    assert.match(source, /patchEventResult\(job\.slug, null, message\)/,
        "a partial repository failure must retain cached rows");
    assert.match(source, /globalInboxFailure/);
    assert.match(source, /inboxBackoffMs/);
    const helpers = load("GitHubHelpers.js");
    assert.match(helpers.GITHUB_QUERIES.events.path, /events\?per_page=30/);
});

test("interactive reads outrank polling and stale Inbox scopes are rejected", () => {
    const source = read("Common/GitHub.qml");
    assert.match(source, /firstBackground = queue\.findIndex\(queued => !queued\.interactive\)/);
    assert.match(source, /kind: "commits"[\s\S]{0,180}?interactive: true/);
    assert.match(source, /kind: "stats"[\s\S]{0,100}?interactive: true/);
    assert.match(source, /job\.generation !== scopeGeneration \|\| inboxSweep === null/);
    assert.match(source,
        /onCiReportsEnabledChanged:[\s\S]*runCache = \(\{\}\);[\s\S]*runBaselines = \(\{\}\);[\s\S]*removeInboxSources[\s\S]*invalidateInboxScope\(\)/,
        "re-enabling workflows must establish a fresh source baseline");
    assert.match(source,
        /onMonitoredKeyChanged:[\s\S]*invalidateInboxScope\(\);[\s\S]*refreshInbox\(true\)/,
        "scope changes refresh repository events even when workflow reporting is off");
});

test("the popover defaults to Inbox and exposes accessible top-level tabs", () => {
    const source = read("Popovers/GitHubPopover.qml");
    assert.match(source, /property string page:\s*"inbox"/);
    assert.match(source, /label:\s*"Inbox"[\s\S]{0,80}?pageName:\s*"inbox"/);
    assert.match(source, /label:\s*"Repositories"[\s\S]{0,80}?pageName:\s*"repos"/);
    assert.match(source, /Accessible\.role:\s*Accessible\.PageTab/);
    assert.match(source, /Accessible\.selected:\s*selected/);
    assert.match(source, /Accessible\.name:\s*"Refresh GitHub repositories and Inbox"/);
    assert.match(source, /property bool settledExpanded:\s*false/);
    assert.match(source, /Accessible\.name:\s*"Settled, "/);
    assert.deepEqual(load("GitHubHelpers.js").inboxSections([]).map(group => group.title),
        ["Active", "Attention", "Updates", "Settled"]);
});

test("the GitHub workspace follows the integrated T3 module hierarchy", () => {
    const source = read("Popovers/GitHubPopover.qml");
    assert.match(source, /padding:\s*T3Theme\.pagePadding/);
    assert.match(source, /surfaceColor:\s*T3Theme\.canvas/);
    assert.match(source, /id:\s*moduleHeader[\s\S]{0,180}?radius:\s*T3Theme\.panelRadius/);
    assert.match(source, /component GroupHeader:[\s\S]*?T3Theme\.tabularNumberFeatures/);
    assert.match(source,
        /height:\s*quiet \? T3Theme\.quietRowHeight : T3Theme\.activeRowHeight/,
        "settled activity should use the same density shift as parked T3 work");
    assert.match(source, /label:\s*"Working"|\?\s*"Working"/);
    assert.match(source, /label:\s*"Repositories"[\s\S]{0,80}?root\.filteredRepos\.length/);
    assert.match(source, /text:\s*"Search repositories"/);
    assert.match(source,
        /page === "repos" && repoSearchText !== ""[\s\S]{0,100}?repoSearchText = ""/,
        "Escape should clear repository search before closing the panel");
});

test("Inbox cards open GitHub and expose local hover/focus settlement actions", () => {
    const source = read("Popovers/GitHubPopover.qml");
    assert.match(source, /function openInbox\(row\)[\s\S]*GitHub\.open\(row\.url\)/);
    assert.match(source,
        /actionsRevealed:[^\n]*inboxHover\.hovered \|\| activeFocus[\s\S]*settleAction\.activeFocus/);
    assert.match(source, /HoverHandler \{\s*id: inboxHover/);
    assert.match(source, /label: inboxCard\.row\.lifecycle === "settled" \? "Unsettle" : "Settle"/);
    assert.match(source, /GitHub\.settleInboxItem\(inboxCard\.row\.key\)/);
    assert.match(source, /GitHub\.unsettleInboxItem\(inboxCard\.row\.key\)/);
    assert.match(source,
        /anchors\.topMargin:\s*showingAction[\s\S]{0,100}?settleAction\.height\) \/ 2 : 7/,
        "passive status should align with the title while inline actions stay centered");
    assert.match(source, /label:\s*"Settle all"/);
    assert.match(source, /onTriggered:\s*GitHub\.settleAllInboxItems\(\)/);
    assert.match(source, /Accessible\.description:\s*"Open on GitHub"/);
    assert.doesNotMatch(source,
        /mark.*(?:notification|thread).*read|\/notifications\/threads\/[^"\s]*\b(?:PATCH|PUT)|\/rerun|\/cancel/i,
        "Inbox actions must remain local and read-only");
    for (const context of ["row.branch", "row.event", "row.actor", "row.number",
        "inboxTimeLabel", "runStatusLabel"])
        assert.ok(source.includes(context), `Inbox rows do not show ${context}`);
});

test("the bar keeps its live-workflow marker clear of the GitHub mark", () => {
    const source = read("Bar/Modules/GitHub.qml");
    const marker = source.match(/\/\/ Running status:[\s\S]*?color:\s*Theme\.barAccent\s*\n\s*\}/)?.[0] ?? "";
    assert.match(marker, /visible:\s*GitHub\.runningCount > 0/);
    assert.match(marker, /width:\s*5[\s\S]*height:\s*5/);
    assert.doesNotMatch(marker, /Animation|Animator|Timer|opacity:/);
    assert.match(source, /GitHub\.badgeTone === "red" \? Theme\.barRed/);
    assert.match(source, /GitHub\.badgeTone === "amber" \? Theme\.barAmber/);
    assert.doesNotMatch(source, /id:\s*badge(?:Count)?\b|GitHub\.badgeVisible/,
        "pending Inbox state must not draw a badge over the GitHub mark");
    assert.match(source, /id:\s*countLabel[\s\S]*text:\s*GitHub\.pendingInboxCount/);
    assert.match(source,
        /githubTooltip\(GitHub\.runningCount,[\s\S]*GitHub\.pendingInboxCount,[\s\S]*GitHub\.unreadRepoCount/);
});

test("settings explain repository refresh and Inbox polling separately", () => {
    const options = read("Settings/ModuleDetailView.qml");
    const watches = read("Settings/GitHubWatchList.qml");
    assert.match(options, /label:\s*"Recent account repos"/);
    assert.match(options, /label:\s*"Repo refresh"/);
    assert.match(options, /optionLabelWidth:\s*156/);
    assert.match(options, /label:\s*"CI reports"[\s\S]{0,220}?view\.opts\.ciActivity/);
    assert.match(options, /Workflow rows in the Inbox/);
    assert.match(options, /failed\/action-required workflows/);
    assert.match(watches, /Every watched repository is additive/);
    assert.match(watches, /Inbox checks repository events and GitHub notifications every minute/);
    assert.match(watches, /GitHub\.watchError\(modelData\)/);
    const defaults = load("SettingsHelpers.js").defaultModOpts().gh;
    assert.deepEqual(Object.keys(defaults).sort(),
        ["badge", "ciActivity", "pollMins", "repos", "toasts", "watch"]);
});
