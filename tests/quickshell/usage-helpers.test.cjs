const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./shell.cjs");

const H = load("UsageHelpers.js");

test("direct usage keeps every supported provider available for sign-in", () => {
    assert.deepEqual(H.providerKeys("direct", {}),
        ["claude", "codex", "kimi", "xai"]);
});

test("CLIProxy usage follows its managed provider inventory", () => {
    const data = {
        xai: { status: "ok", source: "cliproxy", windows: [] },
        kimi: { status: "error", kind: "nocreds" },
        codex: { status: "ok", source: "cliproxy", windows: [] },
        claude: {
            status: "error", kind: "expired", source: "cliproxy",
            accountCount: 2
        }
    };

    assert.deepEqual(H.providerKeys("cliproxy", data),
        ["claude", "codex", "xai"],
        "managed providers stay in stable UI order while absent Kimi is omitted");
    assert.deepEqual(H.providerKeys("cliproxy", {}), []);
});

test("an authoritative CLIProxy inventory miss removes stale cached usage", () => {
    const data = {
        kimi: {
            status: "ok", source: "cliproxy", stale: true,
            staleKind: "nocreds", windows: [{ used: 20 }]
        }
    };

    assert.deepEqual(H.providerKeys("cliproxy", data), []);
});

test("selection moves to the first provider when the proxy inventory changes", () => {
    assert.equal(H.selectedProvider(["codex", "xai"], "kimi"), "codex");
    assert.equal(H.selectedProvider(["codex", "xai"], "xai"), "xai");
    assert.equal(H.selectedProvider([], "kimi"), "kimi");
});
