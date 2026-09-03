const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

const popover = fs.readFileSync(
    path.join(shellDir, "Popovers", "UsagePopover.qml"), "utf8");
const usage = fs.readFileSync(
    path.join(shellDir, "Common", "Usage.qml"), "utf8");
const moduleDetail = fs.readFileSync(
    path.join(shellDir, "Settings", "ModuleDetailView.qml"), "utf8");
const settingsText = fs.readFileSync(
    path.join(shellDir, "Settings", "SettingsTextRow.qml"), "utf8");

test("model usage no longer collects or renders usage history", () => {
    assert.doesNotMatch(popover, /histMode|histBars|USAGE HISTORY/);
    assert.doesNotMatch(usage,
        /property var history|recordSamples|histBars|quickshell-usage-history/);
});

test("model-specific quota periods render in full on their own line", () => {
    assert.ok(popover.includes(
        'return `${m[1]}\\n${m[2].replace(" ", "-")} usage`.toUpperCase();'));
    assert.ok(popover.includes('return `${title.toUpperCase()}\\n\\u00a0`;'),
        "single-line labels should reserve an empty subtitle row");
    assert.match(popover,
        /id:\s*cardLabel[\s\S]{0,600}?wrapMode:\s*Text\.Wrap/);
});

test("usage cards contain their content on padded tile backgrounds", () => {
    assert.match(popover,
        /id:\s*card[\s\S]{0,1100}?color:\s*Theme\.tile[\s\S]{0,100}?border\.color:\s*Theme\.hairlineSoft/);
    assert.match(popover,
        /id:\s*resetCol[\s\S]{0,700}?"resets in " \+ Usage\.formatReset[\s\S]{0,500}?Usage\.formatResetAbs/,
        "relative and absolute reset times should occupy separate contained rows");
});

test("Claude refresh is explicit and stale readings stay visibly qualified", () => {
    assert.match(usage,
        /claudeAutoRefresh[\s\S]{0,250}?--refresh-claude/,
        "the helper flag must follow the persisted setting");
    assert.match(moduleDetail,
        /Keep Claude signed in[\s\S]{0,300}?claudeAutoRefresh/,
        "credential refresh must remain visible and configurable");
    assert.match(usage,
        /if \(fetchProc\.running\)\s*return;/,
        "a refresh must not cancel an in-flight credential rotation");
    assert.match(usage, /p\.stale === true|p\.stale/);
    assert.match(popover, /Showing last known usage/);
    assert.match(popover, /last live/);
    assert.match(popover, /retry in/);
});

test("menubar quota thresholds color text without semantic backgrounds", () => {
    const chips = fs.readFileSync(
        path.join(shellDir, "Bar", "UsageChips.qml"), "utf8");
    assert.doesNotMatch(chips, /Theme\.bar(?:Amber|Red)Bg/);
    assert.match(chips, /status === "crit" \? Theme\.barRedText/);
    assert.match(chips, /status === "warn" \? Theme\.barAmber/);
});

test("provider header shows only the full subscription", () => {
    assert.match(popover, /return root\.p\.plan \|\| "";/);
    assert.doesNotMatch(popover, /root\.p\.(?:account|source)/);
    assert.doesNotMatch(popover, /join\(" · "\)/);
});

test("CLIProxyAPI source and credentials are configurable without persisting the key", () => {
    assert.match(moduleDetail,
        /Usage source[\s\S]{0,500}?CLIProxyAPI[\s\S]{0,800}?Management URL/);
    assert.match(moduleDetail,
        /Verify TLS[\s\S]{0,700}?Management key[\s\S]{0,300}?secret:\s*true/);
    assert.match(usage,
        /--source[\s\S]{0,350}?--cliproxy-url[\s\S]{0,200}?--cliproxy-insecure/);
    assert.match(usage,
        /stdinEnabled:\s*action === "store"[\s\S]{0,250}?write\(pendingKey \+ "\\n"\)/,
        "the management key must go to the private helper over stdin");
    assert.doesNotMatch(usage, /command:[^\n]*pendingKey|args\.push\(pendingKey/);
    assert.match(settingsText, /echoMode:\s*root\.secret \? TextInput\.Password/);
});

test("xAI Grok is configurable and unknown quota percentages stay unknown", () => {
    assert.match(usage, /providerKeys:\s*\["claude", "codex", "kimi", "xai"\]/);
    assert.match(usage, /xai:\s*\{[^}]*title:\s*"xAI Grok"[^}]*icon:\s*"grok"/);
    assert.match(moduleDetail,
        /label:\s*"xAI \/ Grok"[\s\S]{0,500}?view\.opts\.xai/);
    assert.match(usage,
        /typeof w\.used === "number"[\s\S]{0,150}?numeric\.length === 0[\s\S]{0,80}?return -1/,
        "a null xAI percentage must not become 100% remaining on the bar");
    assert.match(popover, /hasUsage:\s*typeof modelData\.used === "number"/);
    assert.match(popover, /text:\s*card\.hasUsage \? card\.remaining : "—"/);
    assert.match(popover, /text:\s*card\.hasUsage \? "% left" : "usage unavailable"/,
        "the xAI tab should still show its reset while its percentage is absent");
});
