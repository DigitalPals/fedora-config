const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawn, spawnSync } = require("node:child_process");
const { shellDir } = require("./shell.cjs");

const helper = path.join(shellDir, "scripts", "network-tool.py");
const speedHelper = path.join(shellDir, "scripts", "network-speedtest.py");

function fixture() {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), "qs-network-test-"));
    const bin = path.join(directory, "bin");
    fs.mkdirSync(bin);
    return {
        directory,
        bin,
        env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
        cleanup() { fs.rmSync(directory, { recursive: true, force: true }); }
    };
}

function executable(base, name, source) {
    const target = path.join(base.bin, name);
    fs.writeFileSync(target, source, { mode: 0o755 });
    return target;
}

function invoke(script, command, request, environment) {
    return spawnSync("python3", [script, command], {
        input: request === undefined ? undefined : `${JSON.stringify(request)}\n`,
        encoding: "utf8",
        env: environment,
        timeout: 10_000
    });
}

function speedCounters(base, interfaceName = "eth0") {
    const root = path.join(base.directory, "counters");
    const statistics = path.join(root, interfaceName, "statistics");
    fs.mkdirSync(statistics, { recursive: true });
    fs.writeFileSync(path.join(statistics, "rx_bytes"), "0\n");
    fs.writeFileSync(path.join(statistics, "tx_bytes"), "0\n");
    base.env.NETWORK_SPEEDTEST_COUNTER_ROOT = root;
    return statistics;
}

test("Wi-Fi credentials reach nmcli only through passwd-file stdin", () => {
    const base = fixture();
    try {
        const log = path.join(base.directory, "nmcli.json");
        base.env.STUB_LOG = log;
        executable(base, "nmcli", `#!/usr/bin/env python3
import json, os, sys
with open(os.environ["STUB_LOG"], "w") as stream:
    json.dump({"argv": sys.argv[1:], "stdin": sys.stdin.read()}, stream)
`);
        const secret = "correct horse battery staple";
        const result = invoke(helper, "wifi", {
            action: "connect",
            uuid: "11111111-2222-3333-4444-555555555555",
            interface: "wlan0",
            security: "WPA2",
            password: secret
        }, base.env);
        assert.equal(result.status, 0, result.stdout + result.stderr);
        assert.doesNotMatch(result.stdout + result.stderr, new RegExp(secret));
        const call = JSON.parse(fs.readFileSync(log, "utf8"));
        assert.deepEqual(call.argv.slice(-2), ["passwd-file", "/dev/stdin"]);
        assert.doesNotMatch(call.argv.join(" "), new RegExp(secret));
        assert.equal(call.stdin, `802-11-wireless-security.psk:${secret}\n`);
    } finally {
        base.cleanup();
    }
});

test("QR payloads are escaped, piped to qrencode, and enterprise sharing is refused", () => {
    const base = fixture();
    try {
        const log = path.join(base.directory, "payload");
        base.env.STUB_LOG = log;
        executable(base, "qrencode", `#!/usr/bin/env python3
import os, sys
open(os.environ["STUB_LOG"], "w").write(sys.stdin.read())
print("00100")
print("01110")
print("11111")
print("01110")
print("00100")
`);
        const result = invoke(helper, "qr", {
            ssid: 'Cafe;North: "desk"',
            security: "WPA2",
            password: "p,a:ss;word\\end",
            hidden: true
        }, base.env);
        assert.equal(result.status, 0, result.stdout + result.stderr);
        const response = JSON.parse(result.stdout);
        assert.deepEqual(response.matrix, ["00100", "01110", "11111", "01110", "00100"]);
        const payload = fs.readFileSync(log, "utf8");
        assert.match(payload, /^WIFI:T:WPA;/);
        assert.match(payload, /S:Cafe\\;North\\: \\"desk\\";/);
        assert.match(payload, /P:p\\,a\\:ss\\;word\\\\end;/);
        assert.match(payload, /H:true;;$/);
        assert.doesNotMatch(result.stdout, /p,a:ss/);

        const profileUuid = "11111111-2222-3333-4444-555555555555";
        const storedSecret = "stored-only-in-helper";
        base.env.STUB_SECRET = storedSecret;
        executable(base, "nmcli", `#!/usr/bin/env python3
import os, sys
a=sys.argv[1:]
U="11111111-2222-3333-4444-555555555555"
if "--show-secrets" in a:
    print(os.environ["STUB_SECRET"]); sys.exit(0)
if "-m" in a and "multiline" in a:
    print(f"NAME:Home\\nUUID:{U}\\nTYPE:802-11-wireless\\nDEVICE:wlan0"); sys.exit(0)
if "uuid" in a:
    print(f"connection.id:Home\\nconnection.uuid:{U}\\nconnection.type:802-11-wireless")
    print("connection.interface-name:wlan0\\nconnection.master:\\nconnection.slave-type:")
    print("connection.controller:\\nconnection.port-type:\\n802-11-wireless.ssid:Home")
    print("802-11-wireless.hidden:no\\n802-11-wireless-security.key-mgmt:wpa-psk")
    print("802-11-wireless.band:\\n802-11-wireless.channel:0\\n802-1x.eap:"); sys.exit(0)
sys.exit(0)
`);
        const automatic = invoke(helper, "qr", {
            uuid: profileUuid, ssid: "Home", security: "WPA2", hidden: false
        }, base.env);
        assert.equal(automatic.status, 0, automatic.stdout + automatic.stderr);
        assert.doesNotMatch(automatic.stdout + automatic.stderr, new RegExp(storedSecret));
        assert.match(fs.readFileSync(log, "utf8"), /P:stored-only-in-helper;/);

        const before = fs.statSync(log).mtimeMs;
        const enterprise = invoke(helper, "qr", {
            ssid: "Corp", security: "WPA2-EAP TLS", password: "never"
        }, base.env);
        assert.notEqual(enterprise.status, 0);
        assert.equal(JSON.parse(enterprise.stdout).code, "not_shareable");
        assert.equal(fs.statSync(log).mtimeMs, before, "qrencode must not run for enterprise Wi-Fi");
    } finally {
        base.cleanup();
    }
});

test("DNS updates filter profiles and roll back earlier modifications", () => {
    const base = fixture();
    try {
        const log = path.join(base.directory, "nmcli.log");
        base.env.STUB_LOG = log;
        executable(base, "nmcli", `#!/usr/bin/env python3
import json, os, sys
a=sys.argv[1:]
E="11111111-1111-1111-1111-111111111111"
W="22222222-2222-2222-2222-222222222222"
T="33333333-3333-3333-3333-333333333333"
B="44444444-4444-4444-4444-444444444444"
if "modify" in a:
    with open(os.environ["STUB_LOG"], "a") as stream: stream.write(json.dumps(a)+"\\n")
    if W in a and any("8.8.8.8" in value for value in a):
        print("simulated modification failure", file=sys.stderr); sys.exit(10)
    sys.exit(0)
if "show" in a and "uuid" not in a:
    print(f"NAME:Wired\\nUUID:{E}\\nTYPE:802-3-ethernet\\nDEVICE:eth0")
    print(f"NAME:Wi-Fi\\nUUID:{W}\\nTYPE:802-11-wireless\\nDEVICE:wlan0")
    print(f"NAME:Tailscale\\nUUID:{T}\\nTYPE:tun\\nDEVICE:tailscale0")
    print(f"NAME:Docker\\nUUID:{B}\\nTYPE:bridge\\nDEVICE:docker0")
    sys.exit(0)
if "uuid" in a:
    u=a[a.index("uuid")+1]
    kind="802-3-ethernet" if u==E else "802-11-wireless"
    name="Wired" if u==E else "Wi-Fi"
    iface="eth0" if u==E else "wlan0"
    print(f"connection.id:{name}\\nconnection.uuid:{u}\\nconnection.type:{kind}\\nconnection.interface-name:{iface}")
    print("connection.master:\\nconnection.slave-type:\\nconnection.controller:\\nconnection.port-type:")
    print("ipv4.method:auto\\nipv4.dns:\\nipv4.ignore-auto-dns:no")
    print("ipv6.method:auto\\nipv6.dns:\\nipv6.ignore-auto-dns:no")
    if u==W: print("802-11-wireless.ssid:Wi-Fi\\n802-11-wireless.band:\\n802-11-wireless.channel:0")
    sys.exit(0)
sys.exit(0)
`);
        const result = invoke(helper, "dns", { provider: "Google" }, base.env);
        assert.notEqual(result.status, 0);
        assert.equal(JSON.parse(result.stdout).code, "dns_modify_failed");
        const calls = fs.readFileSync(log, "utf8").trim().split("\n").map(JSON.parse);
        assert.equal(calls.length, 4,
            "Ethernet apply, Wi-Fi failure, then Wi-Fi and Ethernet rollback");
        assert.ok(calls.every(call => !call.some(value => /33333333|44444444/.test(value))));
        assert.ok(calls[0].includes("8.8.8.8,8.8.4.4"));
        const rollback = calls[3];
        assert.equal(rollback[rollback.indexOf("ipv4.dns") + 1], "");
        assert.equal(rollback[rollback.indexOf("ipv4.ignore-auto-dns") + 1], "no");
    } finally {
        base.cleanup();
    }
});

test("a failed band activation restores the previous profile and reconnects it", () => {
    const base = fixture();
    try {
        const log = path.join(base.directory, "band.log");
        const count = path.join(base.directory, "up-count");
        base.env.STUB_LOG = log;
        base.env.STUB_COUNT = count;
        executable(base, "nmcli", `#!/usr/bin/env python3
import json, os, pathlib, sys
a=sys.argv[1:]; U="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
if "modify" in a:
    with open(os.environ["STUB_LOG"], "a") as stream: stream.write(json.dumps(a)+"\\n")
    sys.exit(0)
if "up" in a:
    p=pathlib.Path(os.environ["STUB_COUNT"]); n=int(p.read_text()) if p.exists() else 0; p.write_text(str(n+1))
    with open(os.environ["STUB_LOG"], "a") as stream: stream.write(json.dumps(a)+"\\n")
    if n==0: print("activation failed", file=sys.stderr); sys.exit(4)
    sys.exit(0)
if "show" in a and "uuid" not in a:
    print(f"NAME:Home\\nUUID:{U}\\nTYPE:802-11-wireless\\nDEVICE:wlan0"); sys.exit(0)
if "show" in a:
    print(f"connection.id:Home\\nconnection.uuid:{U}\\nconnection.type:802-11-wireless")
    print("connection.interface-name:wlan0\\nconnection.master:\\nconnection.slave-type:")
    print("connection.controller:\\nconnection.port-type:\\n802-11-wireless.ssid:Home")
    print("802-11-wireless.band:bg\\n802-11-wireless.channel:0"); sys.exit(0)
sys.exit(0)
`);
        const result = invoke(helper, "band", {
            uuid: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            interface: "wlan0",
            band: "5"
        }, base.env);
        assert.notEqual(result.status, 0);
        assert.equal(JSON.parse(result.stdout).code, "band_activation_failed");
        const calls = fs.readFileSync(log, "utf8").trim().split("\n").map(JSON.parse);
        const modifications = calls.filter(call => call.includes("modify"));
        assert.equal(modifications.length, 2);
        assert.equal(modifications[0][modifications[0].indexOf("802-11-wireless.band") + 1], "a");
        assert.equal(modifications[1][modifications[1].indexOf("802-11-wireless.band") + 1], "bg");
        assert.equal(calls.filter(call => call.includes("up")).length, 2);
    } finally {
        base.cleanup();
    }
});

test("snapshot subprocess failures are bounded", () => {
    const base = fixture();
    try {
        executable(base, "nmcli", "#!/usr/bin/env bash\nexit 0\n");
        executable(base, "ip", "#!/usr/bin/env bash\nsleep 3\nprintf '[]\\n'\n");
        base.env.NETWORK_TOOL_IP_TIMEOUT = "0.1";
        const started = Date.now();
        const result = invoke(helper, "snapshot", undefined, base.env);
        const elapsed = Date.now() - started;
        assert.notEqual(result.status, 0);
        assert.equal(JSON.parse(result.stdout).code, "timeout");
        assert.ok(elapsed < 1500, `bounded lookup took ${elapsed}ms`);
    } finally {
        base.cleanup();
    }
});

test("speed test emits phase, sample, and completion JSON lines", () => {
    const base = fixture();
    try {
        speedCounters(base);
        const calls = path.join(base.directory, "curl.log");
        base.env.STUB_LOG = calls;
        executable(base, "curl", `#!/usr/bin/env python3
import json, os, pathlib, sys, time
a=sys.argv[1:]
if any("api.fast.com" in value for value in a):
    print(json.dumps({"targets":[{"url":"https://fixture.test/transfer"}]})); sys.exit(0)
with open(os.environ["STUB_LOG"], "a") as stream: stream.write(json.dumps(a)+"\\n")
counter="tx_bytes" if "POST" in a else "rx_bytes"
target=pathlib.Path(os.environ["NETWORK_SPEEDTEST_COUNTER_ROOT"])/"eth0"/"statistics"/counter
for _ in range(12):
    value=int(target.read_text().strip() or 0)
    temporary=target.with_name(target.name+"."+str(os.getpid()))
    temporary.write_text(str(value+250000))
    os.replace(temporary, target)
    time.sleep(.02)
`);
        base.env.NETWORK_SPEEDTEST_PHASE_SECONDS = "0.35";
        base.env.NETWORK_SPEEDTEST_SAMPLE_INTERVAL = "0.1";
        base.env.NETWORK_SPEEDTEST_PARALLEL = "2";
        base.env.NETWORK_SPEEDTEST_UPLOAD_BYTES = "1000000";
        const started = Date.now();
        const result = spawnSync("python3", [speedHelper, "--interface", "eth0"], {
            encoding: "utf8", env: base.env, timeout: 5000
        });
        const elapsed = Date.now() - started;
        assert.equal(result.status, 0, result.stdout + result.stderr);
        assert.ok(elapsed >= 600,
            `both sustained phases finished too early (${elapsed}ms)`);
        const records = result.stdout.trim().split("\n").map(JSON.parse);
        assert.equal(records[0].type, "phase");
        assert.equal(records[0].phase, "download");
        assert.ok(records.some(record => record.type === "sample"
            && record.phase === "download"));
        assert.ok(records.some(record => record.type === "phase"
            && record.phase === "upload"));
        assert.ok(records.some(record => record.type === "sample"
            && record.phase === "upload"));
        assert.equal(records.at(-1).type, "completion");
        assert.ok(records.at(-1).downloadMbps > 0);
        assert.ok(records.at(-1).uploadMbps > 0);
        const curlCalls = fs.readFileSync(calls, "utf8").trim().split("\n").map(JSON.parse);
        assert.ok(curlCalls.length >= 4, "parallel workers should sustain both phases");
        assert.ok(curlCalls.every(call => call.includes("--interface")
            && call[call.indexOf("--interface") + 1] === "eth0"));
    } finally {
        base.cleanup();
    }
});

async function waitUntil(predicate, timeoutMs = 3000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
        if (predicate())
            return;
        await new Promise(resolve => setTimeout(resolve, 20));
    }
    assert.fail("timed out waiting for fixture state");
}

test("canceling the speed helper terminates its curl worker", async () => {
    const base = fixture();
    try {
        speedCounters(base);
        const pidFile = path.join(base.directory, "curl.pid");
        base.env.STUB_PID = pidFile;
        base.env.NETWORK_SPEEDTEST_PHASE_SECONDS = "10";
        base.env.NETWORK_SPEEDTEST_PARALLEL = "1";
        executable(base, "curl", `#!/usr/bin/env python3
import json, os, signal, sys, time
if any("api.fast.com" in value for value in sys.argv):
    print(json.dumps({"targets":[{"url":"https://fixture.test/transfer"}]})); sys.exit(0)
open(os.environ["STUB_PID"], "w").write(str(os.getpid()))
def stop(signum, frame): sys.exit(143)
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
while True: time.sleep(.05)
`);
        const child = spawn("python3", [speedHelper, "--interface", "eth0"], {
            env: base.env, stdio: ["ignore", "pipe", "pipe"]
        });
        await waitUntil(() => fs.existsSync(pidFile));
        const curlPid = Number(fs.readFileSync(pidFile, "utf8"));
        child.kill("SIGTERM");
        const exit = await new Promise(resolve => child.on("exit", (code, signal) => resolve({ code, signal })));
        assert.ok(exit.code === 130 || exit.signal === "SIGTERM", JSON.stringify(exit));
        await waitUntil(() => {
            try {
                process.kill(curlPid, 0);
                return false;
            } catch (error) {
                return error.code === "ESRCH";
            }
        });
    } finally {
        base.cleanup();
    }
});
