const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { shellDir } = require("./shell.cjs");

const client = path.join(shellDir, "scripts", "update-client");

function fixture() {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "update-client-"));
    const backend = path.join(root, "backend");
    const release = path.join(root, "release-update");
    const config = path.join(root, "config.yml");
    fs.writeFileSync(backend,
        "#!/usr/bin/env bash\nprintf 'backend:%s\\n' \"$*\"\n", { mode: 0o755 });
    fs.writeFileSync(release,
        "#!/usr/bin/env bash\nprintf 'release:%s\\n' \"$*\"\n", { mode: 0o755 });
    return {
        root,
        backend,
        release,
        config,
        env: {
            ...process.env,
            HOME: root,
            XDG_DATA_HOME: path.join(root, "data"),
            FEDORA_CONFIG_FILE: config,
            FEDORA_CONFIG_RELEASE_UPDATE: release,
            FEDORA_CONFIG_UPDATE_BACKEND: backend,
        },
    };
}

function run(args, env) {
    return spawnSync("bash", [client, ...args], { encoding: "utf8", env });
}

test("an uninitialized source deployment checks cleanly and updates packages", t => {
    const f = fixture();
    t.after(() => fs.rmSync(f.root, { recursive: true, force: true }));

    const check = run(["check"], f.env);
    assert.equal(check.status, 0, check.stderr);
    assert.deepEqual(JSON.parse(check.stdout), {
        currentVersion: "",
        availableVersion: "",
        channel: "",
        available: false,
        managed: false,
    });

    const update = run(["run", "--no-flatpak"], f.env);
    assert.equal(update.status, 0, update.stderr);
    assert.equal(update.stdout, "backend:run --no-flatpak\n");
});

test("an initialized installation retains verified project updates", t => {
    const f = fixture();
    t.after(() => fs.rmSync(f.root, { recursive: true, force: true }));
    fs.writeFileSync(f.config, "config_schema_version: 1\n");

    const check = run(["check"], f.env);
    assert.equal(check.status, 0, check.stderr);
    assert.equal(check.stdout, "release:--check --json\n");

    const update = run(["run", "--no-flatpak"], f.env);
    assert.equal(update.status, 0, update.stderr);
    assert.equal(update.stdout, "release:--no-flatpak\n");
});
