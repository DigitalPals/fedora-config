const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir, load } = require("./shell.cjs");

const H = load("NetworkStatusHelpers.js");

function read(relative) {
    return fs.readFileSync(path.join(shellDir, relative), "utf8");
}

test("only NetworkManager's global connected state is online", () => {
    assert.equal(H.onlineState("connected\n"), true);
    assert.equal(H.onlineState("connected (global)"), true);
    assert.equal(H.onlineState("connecting"), false);
    assert.equal(H.onlineState("connected (local only)"), false);
    assert.equal(H.onlineState("connected (site only)"), false);
    assert.equal(H.onlineState("disconnected"), false);
    assert.equal(H.onlineState("surprising future state"), null);
    assert.equal(H.onlineState(undefined), null);
});

test("one monitored NetworkManager snapshot drives online work", () => {
    const status = read("Common/NetworkStatus.qml");

    assert.match(status,
        /command: \["timeout", "5s", "env", "LC_ALL=C", "nmcli", "--terse",[\s\S]*?"STATE", "general", "status"\]/);
    assert.match(status, /command: \["env", "LC_ALL=C", "nmcli", "monitor"\]/);
    assert.match(status, /onRead: line => snapshotDebounce\.restart\(\)/);
    assert.match(status, /Component\.onCompleted: refresh\(\)/);
});

test("weather and update startup checks wait for the shared online edge", () => {
    const weather = read("Common/Weather.qml");
    const updates = read("Common/Updates.qml");

    assert.match(weather,
        /target: NetworkStatus[\s\S]*?function onOnlineChanged\(\)[\s\S]*?root\.refresh\(\)/);
    assert.match(weather, /running: NetworkStatus\.online/);
    assert.doesNotMatch(weather, /Component\.onCompleted:\s*refresh\(\)/);

    assert.match(updates,
        /target: NetworkStatus[\s\S]*?function onOnlineChanged\(\)[\s\S]*?root\.automaticCheck\(true\)/);
    assert.match(updates, /function automaticCheck\(resetRetries\)/);
    assert.doesNotMatch(updates, /triggeredOnStart:\s*true/);
    assert.match(updates, /checkFailureCount <= 4[\s\S]*?NetworkStatus\.online/);
});
