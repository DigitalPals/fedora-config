const test = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const path = require("node:path");

const repoDir = path.resolve(__dirname, "../..");
const liveHelper = path.join(repoDir, "tests/lib/quickshell-live");

function checkJournal(log) {
    return spawnSync("bash", ["-c", String.raw`
set -u
source "$1"
qs_live_current_journal() {
    printf '%s\n' "$QS_TEST_JOURNAL"
}
qs_live_check_journal
`, "quickshell-live-test", liveHelper], {
        cwd: repoDir,
        encoding: "utf8",
        env: { ...process.env, QS_TEST_JOURNAL: log },
    });
}

test("live journal guard allows the known benign clipping warning", () => {
    const result = checkJournal(
        "WARN qt.qml.propertyCache.append: Member data overrides a base member");
    assert.equal(result.status, 0, result.stderr);
});

test("live journal guard rejects QML JavaScript evaluation errors", async t => {
    for (const [name, diagnostic] of [
        ["TypeError", "Cannot call method 'trim' of null"],
        ["ReferenceError", "missingValue is not defined"],
        ["RangeError", "Maximum call stack size exceeded"],
    ]) {
        await t.test(name, () => {
            const result = checkJournal(
                `WARN scene: @Common/Theme.qml[23:-1]: ${name}: ${diagnostic}`);
            assert.equal(result.status, 1,
                `${name} unexpectedly passed the live journal guard`);
            assert.match(result.stderr, /contains QML\/runtime errors/);
            assert.match(result.stderr, new RegExp(name));
        });
    }
});
