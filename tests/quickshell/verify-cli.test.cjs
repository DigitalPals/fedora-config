const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const child = require("node:child_process");
const repoRoot = path.resolve(__dirname, "../..");

function invoke(args) {
    return child.spawnSync(path.join(repoRoot, "verify"), args, {
        cwd: repoRoot,
        encoding: "utf8",
    });
}

test("verify documents explicit source, system, quick, and JSON scopes", () => {
    const result = invoke(["--help"]);
    assert.equal(result.status, 0);
    for (const flag of ["--source", "--system", "--quick", "--json", "--require-hyprland"])
        assert.match(result.stdout, new RegExp(flag));
});

test("verify rejects unknown and contradictory options before running checks", () => {
    const unknown = invoke(["--definitely-not-real"]);
    assert.equal(unknown.status, 2);
    assert.match(unknown.stderr, /unknown argument/);
    assert.doesNotMatch(unknown.stdout + unknown.stderr, /PASS  /);

    const conflict = invoke(["--source", "--system"]);
    assert.equal(conflict.status, 2);
    assert.match(conflict.stderr, /choose only one/);

    const irrelevant = invoke(["--source", "--require-hyprland"]);
    assert.equal(irrelevant.status, 2);
    assert.match(irrelevant.stderr, /applies only to system checks/);
});

test("JSON output has stable per-scope result fields", () => {
    const source = fs.readFileSync(path.join(repoRoot, "verify"), "utf8");
    for (const field of ["ok", "scope", "source", "system", "ran", "exitCode", "output"])
        assert.match(source, new RegExp(`"${field}"`));
    assert.match(source, /json\.dumps/);
    assert.match(source, /"ok": code == 0 if ran else None/);
});
