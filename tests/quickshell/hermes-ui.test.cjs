const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir, load } = require("./shell.cjs");

const repo = path.resolve(shellDir, "../../../..");
const SettingsHelpers = load("SettingsHelpers.js");
const PanelRegistry = load("PanelRegistryData.js");

function shellPath(relative) {
    return path.join(shellDir, relative);
}

function read(relative) {
    return fs.readFileSync(shellPath(relative), "utf8");
}

function readRepo(relative) {
    return fs.readFileSync(path.join(repo, relative), "utf8");
}

test("Hermes is one configurable chip and one registry-owned popover", () => {
    const defaults = SettingsHelpers.defaults();
    const right = defaults.mods.right.map(module => module.id);
    assert.equal(right[right.indexOf("t3") + 1], "hermes");
    assert.equal(SettingsHelpers.moduleGroup("hermes"), "chip");
    assert.ok(SettingsHelpers.DETAIL_IDS.includes("hermes"));
    assert.deepEqual(defaults.modOpts.hermes,
        { showLabel: true, activityDetail: "verb" });
    assert.deepEqual(PanelRegistry.byName("hermes"), {
        name: "hermes", island: "right", moduleId: "hermes",
        source: "Popovers/HermesPopover.qml"
    });

    const bar = read("Bar/Bar.qml");
    const module = read("Bar/Modules/Hermes.qml");
    assert.match(bar, /hermes:\s*"Modules\/Hermes\.qml"/);
    assert.match(module, /moduleId:\s*"hermes"/);
    assert.match(module, /HermesChip\s*\{/);
    assert.match(module, /panelName:\s*"hermes"/);
});

test("responsive chip measurements survive their compact state", () => {
    const bar = read("Bar/Bar.qml");
    const hermes = read("Bar/HermesChip.qml");
    const t3 = read("Bar/T3Chip.qml");
    const github = read("Bar/Modules/GitHub.qml");
    const clock = read("Bar/Modules/Clock.qml");

    for (const [name, chip] of [["Hermes", hermes], ["T3", t3]]) {
        assert.match(chip,
            /detailSaving:\s*labelText\.implicitWidth\s*\+\s*spacing/,
            `${name} must retain its expanded measurement while compact`);
        assert.doesNotMatch(chip,
            /detailSaving:\s*labelText\.visible/,
            `${name} must not erase its saving when its label is hidden`);
    }
    assert.match(github,
        /detailSaving:\s*detailAvailable[\s\S]{0,80}?countLabel\.implicitWidth/);
    assert.doesNotMatch(github,
        /detailSaving:\s*countLabel\.visible/);
    assert.match(clock,
        /detailSaving:\s*Settings\.modOpts\.clock\.showDate/);
    assert.doesNotMatch(clock, /detailSaving:\s*showDate\s*\?/);
    assert.match(bar,
        /id:\s*fitTimer[\s\S]{0,600}?interval:\s*Math\.max\(1,\s*Theme\.expandDuration\s*\+\s*20\)/,
        "fit decisions must wait for animated widths to settle");
    assert.doesNotMatch(bar,
        /id:\s*fitTimer[\s\S]{0,120}?interval:\s*0/);
});

test("the menubar projects priority conversation activity", () => {
    const chip = read("Bar/HermesChip.qml");
    const facade = read("Common/Hermes.qml");
    const helpers = read("Common/HermesHelpers.js");

    assert.ok(chip.indexOf("Hermes.attentionCount > 0")
        < chip.indexOf("Hermes.errorCount > 0"));
    assert.ok(chip.indexOf("Hermes.errorCount > 0")
        < chip.indexOf("Hermes.workingCount > 1"));
    assert.match(chip,
        /Hermes\.workingCount === 1[\s\S]{0,120}?Hermes\.activityLabel/);
    assert.match(chip, /Hermes\.unreadCount > 0/);
    assert.match(chip, /Hermes\.doneCount > 0/);
    assert.match(chip, /text:\s*"⚕"/);
    assert.match(chip, /Accessible\.ignored:\s*true/);
    assert.match(facade,
        /\["full", "verb", "generic"\][\s\S]{0,100}?opts\.activityDetail/);
    assert.match(helpers,
        /if \(detailMode === "full" && conversation\.statusText\)/);
});

test("the transport reconciles native WebUI conversations without replaying prompts", () => {
    const connection = read("Common/HermesConnection.qml");
    const rpc = read("Common/HermesRpc.qml");
    const conversations = read("Common/HermesConversations.qml");
    const facade = read("Common/Hermes.qml");

    assert.match(connection, /"ws:\/\/127\.0\.0\.1:9120\/ws"/);
    assert.match(connection, /Quickshell\.env\("HERMES_MENUBAR_WS_URL"\)/);
    assert.match(connection, /generation !== root\.generation/);
    assert.match(connection, /retrySecs = Math\.min\(60, retrySecs \* 2\)/);
    assert.match(rpc, /function abortAll\(reason\)/);
    assert.doesNotMatch(rpc, /retryTimer|scheduleRetry|pendingReplay|replayQueue/);
    assert.match(conversations,
        /HermesRpc\.request\("conversations\.list"/);
    assert.match(conversations,
        /HermesRpc\.request\("session\.history"[\s\S]*?HermesRpc\.request\("session\.status"/);
    assert.match(conversations, /"\/hermes-menubar\/client\.json"/);
    assert.match(facade, /function onOpened\(\) \{ root\.hello\(\); \}/);
});

test("new chat is the non-persisted default and first send creates a WebUI session", () => {
    const conversations = read("Common/HermesConversations.qml");
    const facade = read("Common/Hermes.qml");
    const bridge = readRepo(
        "roles/desktop/files/hermes-menubar-bridge/hermes_bridge.py");
    const service = readRepo(
        "roles/desktop/templates/hermes-menubar-bridge.service.j2");

    assert.match(conversations, /property string selectedConversationId:\s*""/);
    assert.match(conversations, /title:\s*"New chat"/);
    assert.match(conversations,
        /function createConversation[\s\S]*?"conversations\.create"/);
    assert.doesNotMatch(conversations,
        /selectedConversationId[\s\S]{0,100}?settings\.setValue/);
    assert.match(facade,
        /function submit\(conversationId, text\)[\s\S]*?conversationId === ""[\s\S]*?createConversation[\s\S]*?root\.submit\(conversation\.id, prompt\)/);
    assert.match(facade,
        /function startNewChat\(\)[\s\S]*?selectConversation\("", false\)/);
    assert.match(bridge, /GET", "\/api\/sessions\?exclude_hidden=1"/);
    assert.match(bridge, /POST", "\/api\/session\/new"/);
    assert.match(bridge, /POST",\s*"\/api\/session\/delete"/);
    assert.match(service, /\/conversations\.json/);
    assert.doesNotMatch(bridge, /"channels\.|"channel\./);
    assert.doesNotMatch(bridge, /HomeAssistant|"general"|"homeassistant"/);
});

test("historical chats are selectable from a dropdown and no channel rail remains", () => {
    const commonQmldir = read("Common/qmldir");
    const popoverQmldir = read("Popovers/qmldir");
    const inbox = read("Popovers/HermesInboxPage.qml");

    assert.match(commonQmldir, /singleton HermesConversations/);
    assert.doesNotMatch(commonQmldir, /HermesChannels/);
    assert.doesNotMatch(popoverQmldir, /HermesChannelRail/);
    assert.equal(fs.existsSync(shellPath("Common/HermesChannels.qml")), false);
    assert.equal(fs.existsSync(shellPath("Popovers/HermesChannelRail.qml")), false);
    assert.match(inbox,
        /pickerRows:\s*\[HermesConversations\.newConversation\][\s\S]{0,120}?Hermes\.conversations/);
    assert.match(inbox, /ListView\s*\{[\s\S]{0,500}?cacheBuffer:\s*0/,
        "long WebUI history must use a virtualized dropdown");
    assert.match(inbox,
        /model:\s*root\.pickerOpen\s*\?\s*root\.pickerRows\s*:\s*\[\]/,
        "a closed history dropdown must not retain conversation delegates");
    assert.match(inbox, /\? "New chat" : "Conversation " \+ modelData\.title/);
    assert.match(inbox, /Hermes\.selectConversation\(conversationId\)/);
    assert.match(inbox, /HermesTranscript\s*\{/);
    assert.match(inbox, /HermesRequestCard\s*\{/);
    assert.match(inbox, /HermesComposer\s*\{/);
    assert.doesNotMatch(inbox, /HermesChannelRail/);
});

test("remote WebUI sign-in remains primary, session-aware, and secret-safe", () => {
    const facade = read("Common/Hermes.qml");
    const chip = read("Bar/HermesChip.qml");
    const popover = read("Popovers/HermesPopover.qml");
    const auth = read("Popovers/HermesAuthPanel.qml");

    assert.match(facade,
        /remoteState === "connected" && remoteAuthenticated/);
    assert.match(facade, /HermesRpc\.request\("remote\.status", \{\}/);
    assert.match(facade,
        /HermesRpc\.request\("remote\.login", \{[\s\S]{0,120}?url: safeUrl,[\s\S]{0,80}?password: password/);
    assert.match(facade, /HermesRpc\.request\("remote\.logout", \{\}/);
    assert.doesNotMatch(facade,
        /property\s+(?:string|var)\s+\w*password/i);
    assert.match(auth, /label:\s*"Hermes WebUI URL"/);
    assert.match(auth, /label:\s*"WebUI password"/);
    assert.match(auth, /echoMode:\s*TextInput\.Password/);
    assert.match(auth,
        /Hermes\.loginRemote\(url, remotePasswordField\.text,[\s\S]{0,300}?remotePasswordField\.text = ""/);
    assert.match(auth, /never retained or displayed by Quickshell/);
    assert.match(popover, /Remote · " \+ Hermes\.remoteOrigin/);
    assert.match(chip, /remote WebUI session expired/);
});

test("streaming, tools, requests, stop, steering, and private input use conversation ids", () => {
    const facade = read("Common/Hermes.qml");
    const conversations = read("Common/HermesConversations.qml");
    const composer = read("Popovers/HermesComposer.qml");
    const request = read("Popovers/HermesRequestCard.qml");
    const tool = read("Popovers/HermesToolCard.qml");
    const bridge = readRepo(
        "roles/desktop/files/hermes-menubar-bridge/hermes_bridge.py");

    assert.match(conversations, /Helpers\.applyMessageEvent/);
    assert.match(conversations, /Helpers\.applyToolEvent/);
    assert.match(conversations, /Helpers\.applyRequestEvent/);
    for (const method of ["approval.respond", "clarify.respond", "sudo.respond",
                          "secret.respond"])
        assert.ok(facade.includes(`"${method}"`), `${method} is not exposed`);
    assert.match(composer, /Hermes\.submit\(conversationId, promptEdit\.text\)/);
    assert.match(composer, /Hermes\.interrupt\(root\.conversationId\)/);
    assert.match(composer, /Hermes\.steer\(conversationId, promptEdit\.text\)/);
    assert.match(facade,
        /function steer\(conversationId, text\)[\s\S]*?"session\.steer"/);
    assert.match(request, /TextInput\.Password/);
    assert.match(request,
        /request\.kind === "sudo" \|\| root\.request\.kind === "secret"/);
    assert.match(bridge, /params\.get\("choice"\) or params\.get\("decision"\)/);
    assert.match(tool, /progress_activity/);
});

test("Hermes history projects prose, one tool activity line, pagination, and session state", () => {
    const helpers = read("Common/HermesHelpers.js");
    const conversations = read("Common/HermesConversations.qml");
    const transcript = read("Popovers/HermesTranscript.qml");
    const tool = read("Popovers/HermesToolCard.qml");
    const bridge = readRepo(
        "roles/desktop/files/hermes-menubar-bridge/hermes_bridge.py");

    assert.match(helpers, /function renderableMessage/);
    assert.match(helpers, /return "metadata"/,
        "unknown protocol roles must not default to assistant prose");
    assert.match(helpers, /function transcriptItems/);
    assert.match(conversations, /Helpers\.normalizeHistory/);
    assert.match(conversations, /function loadEarlier/);
    assert.match(conversations, /before:\s*Math\.max/);
    assert.match(transcript, /model:\s*root\.shownItems/);
    assert.match(transcript, /Helpers\.transcriptItems\(allMessages, \[\]\)/,
        "persisted tool records must not become transcript rows");
    assert.match(transcript, /property var latestTool:/);
    assert.equal((transcript.match(/HermesToolCard\s*\{/g) || []).length, 1,
        "tool activity must render through one updating line");
    assert.match(transcript, /HermesConversations\.loadEarlier/);
    assert.match(transcript, /sessionState\.reasoning/);
    assert.match(transcript, /property string messageText:\s*String/,
        "optional remote text must not assign undefined to QString");
    assert.match(tool, /tool\.output/);
    assert.match(tool, /property string toolName:\s*String/,
        "optional historical tool labels must have a QString-safe fallback");
    assert.match(tool, /implicitHeight:\s*30/);
    assert.match(tool, /property string detailText:/);
    assert.doesNotMatch(tool, /expanded|"INPUT"|"OUTPUT"/,
        "tool activity must stay a single non-expanding line");
    assert.match(bridge, /project_remote_transcript/);
    assert.match(bridge, /msg_limit=/);
    assert.match(bridge, /"session\.todos"/);
    assert.match(bridge, /"session\.context"/);
    assert.match(bridge, /"session\.goal"/);
    assert.match(bridge, /"session\.warning"/);
});
