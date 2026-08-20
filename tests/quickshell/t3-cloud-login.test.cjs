const test = require("node:test");
const assert = require("node:assert/strict");
const { spawn } = require("node:child_process");
const {
    createHash,
    createPublicKey,
    generateKeyPairSync,
    verify,
} = require("node:crypto");
const fs = require("node:fs");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { shellDir } = require("./shell.cjs");

const repoDir = path.resolve(__dirname, "../..");

function readRepo(relativePath) {
    return fs.readFileSync(path.join(repoDir, relativePath), "utf8");
}

function readShell(relativePath) {
    return fs.readFileSync(path.join(shellDir, relativePath), "utf8");
}

function runProcess(command, args, env, input = "") {
    return new Promise((resolve, reject) => {
        const child = spawn(command, args, { env });
        let stdout = "";
        let stderr = "";
        const timeout = setTimeout(() => {
            child.kill();
            reject(new Error(`Timed out running ${command}; stdout=${stdout}; stderr=${stderr}`));
        }, 10_000);
        child.stdout.setEncoding("utf8");
        child.stderr.setEncoding("utf8");
        child.stdout.on("data", chunk => stdout += chunk);
        child.stderr.on("data", chunk => stderr += chunk);
        child.once("error", error => {
            clearTimeout(timeout);
            reject(error);
        });
        child.once("close", status => {
            clearTimeout(timeout);
            resolve({ status, stdout, stderr });
        });
        child.stdin.end(input);
    });
}

function runNode(script, command, env) {
    return runProcess(process.execPath, [script, command], env);
}

function decodeJwtPart(value, part) {
    return JSON.parse(Buffer.from(value.split(".")[part], "base64url").toString("utf8"));
}

test("the signed-out T3 panel presents T3 Connect login instead of pairing", () => {
    const chip = readShell("Bar/T3Chip.qml");
    const facade = readShell("Common/T3Code.qml");
    const popover = readShell("Popovers/T3CodePopover.qml");
    const inbox = readShell("Popovers/T3InboxPage.qml");
    const connection = readShell("Common/T3Connection.qml");
    const shell = readShell("shell.qml");
    const helper = readShell("scripts/t3-cloud.mjs");

    assert.doesNotMatch(popover, /function openDesktopClient\(\)/);
    assert.doesNotMatch(popover, /text: "Open T3 Code"/);
    assert.doesNotMatch(inbox, /Create a pairing link|Pair this panel|Paste link|Open Nightly/);
    assert.doesNotMatch([chip, facade, popover, inbox, connection, helper].join("\n"),
        /T3 Cloud/, "T3 Connect must be used consistently as the product name");
    assert.match(inbox, /title: T3Code\.cloudLoginRunning \? "Finish in your browser"/);
    assert.match(inbox, /label: T3Code\.cloudLoginRunning \? "Waiting for browser…"/);
    assert.match(inbox, /onTriggered: T3Code\.loginCloud\(\)/);
    assert.match(inbox, /Sign in with Google or GitHub to access your linked environments/);
    assert.doesNotMatch(inbox, /Sign in to T3 Connect|Refresh T3 Connect/);
    assert.doesNotMatch(popover, /T3 Connect · signed out|T3 Connect · signing in/);
    assert.match(popover, /id: footer\s+visible: T3Code\.state === "connected"/);
    assert.match(connection, /t3-cloud\.mjs", "login"/);
    assert.match(connection, /t3-cloud\.mjs", "ticket"/);
    assert.match(connection, /Quickshell\.env\("XDG_STATE_HOME"\)\s*\|\|/,
        "an unset XDG_STATE_HOME must fall back instead of producing an empty watcher path");
    assert.match(shell, /function open\(name: string\): void \{\s*Popouts\.openPanel\(name\)/);
    assert.match(helper, /https:\/\/app\.t3\.codes/);
    assert.match(helper, /callbackPort: Number\([^\n]+34338/);
    assert.match(helper, /qs", \["ipc", "call", "popouts", "open", "t3code"\]/);
    assert.match(helper, /"wl-paste", \[/);
});

test("hosted handoff completes when its matching authorization code is copied", async t => {
    const tokenRequests = [];
    const server = http.createServer((request, response) => {
        let body = "";
        request.setEncoding("utf8");
        request.on("data", chunk => body += chunk);
        request.on("end", () => {
            tokenRequests.push({ url: request.url, body });
            response.writeHead(200, { "content-type": "application/json" });
            response.end(JSON.stringify({
                access_token: "clerk-access-token",
                refresh_token: "clerk-refresh-token",
                expires_in: 3600,
            }));
        });
    });
    await new Promise((resolve, reject) => {
        server.once("error", reject);
        server.listen(0, "127.0.0.1", resolve);
    });
    t.after(() => new Promise(resolve => server.close(resolve)));

    const callbackProbe = http.createServer();
    await new Promise((resolve, reject) => {
        callbackProbe.once("error", reject);
        callbackProbe.listen(0, "127.0.0.1", resolve);
    });
    const callbackPort = callbackProbe.address().port;
    await new Promise(resolve => callbackProbe.close(resolve));

    const temporaryHome = fs.mkdtempSync(path.join(os.tmpdir(), "t3-cloud-oob-"));
    t.after(() => fs.rmSync(temporaryHome, { recursive: true, force: true }));
    const binDir = path.join(temporaryHome, "bin");
    const openedUrlPath = path.join(temporaryHome, "opened-url");
    const clipboardPath = path.join(temporaryHome, "clipboard");
    const toolLogPath = path.join(temporaryHome, "tool-log");
    fs.mkdirSync(binDir);
    fs.writeFileSync(path.join(binDir, "xdg-open"), `#!/usr/bin/env node
const fs = require("node:fs");
const url = process.argv[2];
fs.appendFileSync(process.env.T3_TEST_TOOL_LOG, "xdg-open " + url + "\\n");
const state = new URL(url).hash.slice(1);
const expected = new URLSearchParams(state).get("state");
fs.writeFileSync(process.env.T3_TEST_OPENED_URL, url);
fs.writeFileSync(process.env.T3_TEST_CLIPBOARD, "hosted-authorization-code." + expected);
`, { mode: 0o755 });
    fs.writeFileSync(path.join(binDir, "wl-paste"), `#!/usr/bin/env node
const { spawn } = require("node:child_process");
const fs = require("node:fs");
const watch = process.argv.indexOf("--watch");
const command = process.argv[watch + 1];
const args = process.argv.slice(watch + 2);
fs.appendFileSync(process.env.T3_TEST_TOOL_LOG, "wl-paste " + JSON.stringify(process.argv) + "\\n");
function forward() {
    if (!fs.existsSync(process.env.T3_TEST_CLIPBOARD)) {
        setTimeout(forward, 10);
        return;
    }
    const child = spawn(command, args, { stdio: ["pipe", "pipe", "inherit"] });
    fs.appendFileSync(process.env.T3_TEST_TOOL_LOG, "forward " + command + " " + JSON.stringify(args) + "\\n");
    child.stdout.pipe(process.stdout);
    child.stdin.end(fs.readFileSync(process.env.T3_TEST_CLIPBOARD));
    child.once("close", () => setInterval(() => undefined, 1000));
}
forward();
`, { mode: 0o755 });

    const address = server.address();
    const backend = `http://127.0.0.1:${address.port}`;
    const script = path.join(shellDir, "scripts/t3-cloud.mjs");
    const moduleUrl = pathToFileURL(script).href;
    const env = {
        ...process.env,
        HOME: temporaryHome,
        PATH: `${binDir}:${process.env.PATH}`,
        T3_TEST_OPENED_URL: openedUrlPath,
        T3_TEST_CLIPBOARD: clipboardPath,
        T3_TEST_TOOL_LOG: toolLogPath,
        T3CODE_CLOUD_STATE_DIR: path.join(temporaryHome, "state"),
        T3CODE_HOSTED_APP_URL: backend,
        T3CODE_CLERK_URL: backend,
        T3CODE_CLOUD_CALLBACK_PORT: String(callbackPort),
    };
    const code = `
import { interactiveLogin } from ${JSON.stringify(moduleUrl)};
process.stdout.write(JSON.stringify(await interactiveLogin()));
`;
    let result;
    try {
        result = await runProcess(process.execPath,
            ["--input-type=module", "--eval", code], env);
    } catch (error) {
        const toolLog = fs.existsSync(toolLogPath) ? fs.readFileSync(toolLogPath, "utf8") : "";
        throw new Error(`${error.message}; tools=${toolLog}`);
    }

    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stderr, "");
    assert.deepEqual(JSON.parse(result.stdout), {
        accessToken: "clerk-access-token",
        refreshToken: "clerk-refresh-token",
        expiresAtEpochMs: JSON.parse(result.stdout).expiresAtEpochMs,
        identity: "",
    });
    assert.ok(JSON.parse(result.stdout).expiresAtEpochMs > Date.now());
    const openedUrl = new URL(fs.readFileSync(openedUrlPath, "utf8"));
    assert.equal(new URLSearchParams(openedUrl.hash.slice(1)).get("port"),
        String(callbackPort));
    assert.equal(tokenRequests.length, 1);
    const tokenForm = new URLSearchParams(tokenRequests[0].body);
    assert.equal(tokenForm.get("code"), "hosted-authorization-code");
    assert.equal(tokenForm.get("redirect_uri"), `${backend}/connect/callback`);
    assert.equal(typeof tokenForm.get("code_verifier"), "string");
});

test("the T3 Connect helper emits verifiable T3-compatible DPoP proofs", async () => {
    const script = path.join(shellDir, "scripts/t3-cloud.mjs");
    const helper = await import(pathToFileURL(script).href + `?dpop=${Date.now()}`);
    assert.equal(helper.parseConnectAuthCode("authorization.expected-state", "expected-state"),
        "authorization");
    assert.equal(helper.parseConnectAuthCode("authorization.wrong-state", "expected-state"),
        null);
    const generated = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
    const privateJwk = generated.privateKey.export({ format: "jwk" });
    const publicJwk = {
        kty: privateJwk.kty,
        crv: privateJwk.crv,
        x: privateJwk.x,
        y: privateJwk.y,
    };
    const proof = helper.createDpopProof({
        method: "post",
        url: "https://environment.example.test/api/auth/websocket-ticket?ignored=yes",
        accessToken: "environment-access-token",
        key: { privateKey: generated.privateKey, publicJwk },
        now: 1_800_000_000_000,
    });

    const [encodedHeader, encodedPayload, encodedSignature] = proof.split(".");
    const signature = Buffer.from(encodedSignature, "base64url");
    assert.deepEqual(decodeJwtPart(proof, 0), {
        typ: "dpop+jwt",
        alg: "ES256",
        jwk: publicJwk,
    });
    const payload = decodeJwtPart(proof, 1);
    assert.deepEqual(payload, {
        htm: "POST",
        htu: "https://environment.example.test/api/auth/websocket-ticket",
        jti: payload.jti,
        iat: 1_800_000_000,
        ath: createHash("sha256").update("environment-access-token").digest("base64url"),
    });
    assert.equal(verify("sha256", Buffer.from(`${encodedHeader}.${encodedPayload}`), {
        key: createPublicKey(generated.privateKey),
        dsaEncoding: "ieee-p1363",
    }, signature), true);
    const p256Order = BigInt(
        "0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551");
    assert.ok(BigInt(`0x${signature.subarray(32).toString("hex")}`) <= p256Order / 2n,
        "T3's noble-curves verifier requires canonical low-S signatures");
    assert.equal(helper.computeDpopThumbprint(publicJwk), createHash("sha256")
        .update(JSON.stringify({
            crv: publicJwk.crv,
            kty: publicJwk.kty,
            x: publicJwk.x,
            y: publicJwk.y,
        })).digest("base64url"));
});

test("the T3 Connect helper discovers, authorizes, and tickets a linked environment", async t => {
    const requests = [];
    const server = http.createServer((request, response) => {
        let body = "";
        request.setEncoding("utf8");
        request.on("data", chunk => body += chunk);
        request.on("end", () => {
            requests.push({
                method: request.method,
                url: request.url,
                headers: request.headers,
                body,
            });
            response.writeHead(200, { "content-type": "application/json" });
            const address = server.address();
            const base = `http://127.0.0.1:${address.port}`;
            if (request.method === "GET" && request.url === "/v1/environments") {
                response.end(JSON.stringify({ environments: [{
                    environmentId: "env-nightly",
                    label: "Nightly workstation",
                    endpoint: {
                        httpBaseUrl: base,
                        wsBaseUrl: base.replace("http:", "ws:"),
                        providerKind: "cloudflare",
                    },
                    linkedAt: "2026-08-19T18:00:00.000Z",
                }] }));
            } else if (request.method === "POST"
                    && request.url === "/v1/client/dpop-token") {
                response.end(JSON.stringify({
                    access_token: "relay-access-token",
                    issued_token_type: "urn:ietf:params:oauth:token-type:access_token",
                    token_type: "DPoP",
                    expires_in: 300,
                    scope: "environment:connect",
                }));
            } else if (request.method === "POST"
                    && request.url === "/v1/environments/env-nightly/connect") {
                response.end(JSON.stringify({
                    environmentId: "env-nightly",
                    endpoint: {
                        httpBaseUrl: base,
                        wsBaseUrl: base.replace("http:", "ws:"),
                        providerKind: "cloudflare",
                    },
                    credential: "environment-bootstrap",
                    expiresAt: "2026-08-19T22:00:00.000Z",
                }));
            } else if (request.method === "POST" && request.url === "/oauth/token") {
                response.end(JSON.stringify({
                    access_token: "environment-access-token",
                    issued_token_type: "urn:ietf:params:oauth:token-type:access_token",
                    token_type: "DPoP",
                    expires_in: 3600,
                    scope: "orchestration:read orchestration:operate terminal:operate review:write relay:read",
                }));
            } else if (request.method === "POST"
                    && request.url === "/api/auth/websocket-ticket") {
                response.end(JSON.stringify({ ticket: "short-lived-ticket" }));
            } else {
                response.statusCode = 404;
                response.end(JSON.stringify({ error: "not_found" }));
            }
        });
    });
    await new Promise((resolve, reject) => {
        server.once("error", reject);
        server.listen(0, "127.0.0.1", resolve);
    });
    t.after(() => new Promise(resolve => server.close(resolve)));

    const temporaryHome = fs.mkdtempSync(path.join(os.tmpdir(), "t3-panel-cloud-"));
    t.after(() => fs.rmSync(temporaryHome, { recursive: true, force: true }));

    const address = server.address();
    const backend = `http://127.0.0.1:${address.port}`;
    const stateRoot = path.join(temporaryHome, "state");
    const privateState = path.join(stateRoot, "t3code-cloud");
    fs.mkdirSync(privateState, { recursive: true, mode: 0o700 });
    fs.writeFileSync(path.join(privateState, "credentials.json"), JSON.stringify({
        accessToken: "clerk-access-token",
        refreshToken: "clerk-refresh-token",
        expiresAtEpochMs: Date.now() + 60 * 60 * 1000,
        identity: "nightly@example.test",
    }), { mode: 0o600 });

    const script = path.join(shellDir, "scripts/t3-cloud.mjs");
    const env = {
        ...process.env,
        HOME: temporaryHome,
        T3CODE_CLOUD_STATE_DIR: stateRoot,
        T3CODE_HOSTED_APP_URL: backend,
        T3CODE_CLERK_URL: backend,
        T3CODE_RELAY_URL: backend,
    };
    const connected = await runNode(script, "connect", env);
    assert.equal(connected.status, 0, connected.stderr);
    assert.equal(connected.stderr, "");
    assert.deepEqual(JSON.parse(connected.stdout), {
        status: "connected",
        identity: "nightly@example.test",
        environmentId: "env-nightly",
        environmentLabel: "Nightly workstation",
    });
    assert.doesNotMatch(connected.stdout,
        /clerk-access-token|relay-access-token|environment-access-token|environment-bootstrap/);

    const statePath = path.join(stateRoot, "t3code-bar.json");
    const state = JSON.parse(fs.readFileSync(statePath, "utf8"));
    assert.deepEqual({
        authMode: state.authMode,
        cloudStatus: state.cloudStatus,
        cloudIdentity: state.cloudIdentity,
        environmentId: state.environmentId,
        environmentLabel: state.environmentLabel,
        httpBaseUrl: state.httpBaseUrl,
        wsBaseUrl: state.wsBaseUrl,
        accessToken: state.accessToken,
        tokenType: state.tokenType,
    }, {
        authMode: "cloud",
        cloudStatus: "connected",
        cloudIdentity: "nightly@example.test",
        environmentId: "env-nightly",
        environmentLabel: "Nightly workstation",
        httpBaseUrl: backend,
        wsBaseUrl: backend.replace("http:", "ws:"),
        accessToken: "environment-access-token",
        tokenType: "DPoP",
    });
    assert.equal(fs.statSync(statePath).mode & 0o777, 0o600);
    assert.equal(fs.statSync(path.join(privateState, "dpop-key.json")).mode & 0o777, 0o600);

    const listed = requests.find(item => item.url === "/v1/environments");
    assert.equal(listed.headers.authorization, "Bearer clerk-access-token");
    const relayExchange = requests.find(item => item.url === "/v1/client/dpop-token");
    assert.match(relayExchange.headers.dpop, /^[^.]+\.[^.]+\.[^.]+$/);
    const relayForm = new URLSearchParams(relayExchange.body);
    assert.equal(relayForm.get("client_id"), "t3-web");
    assert.equal(relayForm.get("scope"), "environment:connect");
    const relayConnect = requests.find(item => item.url.endsWith("/connect"));
    assert.equal(relayConnect.headers.authorization, "DPoP relay-access-token");
    assert.equal(typeof JSON.parse(relayConnect.body).clientKeyThumbprint, "string");
    const environmentExchange = requests.find(item => item.url === "/oauth/token");
    assert.equal(new URLSearchParams(environmentExchange.body).get("subject_token"),
        "environment-bootstrap");

    const ticket = await runNode(script, "ticket", env);
    assert.equal(ticket.status, 0, ticket.stderr);
    assert.equal(ticket.stderr, "");
    assert.equal(new URL(JSON.parse(ticket.stdout).socketUrl).searchParams.get("wsTicket"),
        "short-lived-ticket");
    const ticketRequest = requests.find(item => item.url === "/api/auth/websocket-ticket");
    assert.equal(ticketRequest.headers.authorization, "DPoP environment-access-token");
    assert.match(ticketRequest.headers.dpop, /^[^.]+\.[^.]+\.[^.]+$/);
});

test("the nightly launcher forwards production OAuth callback URLs unchanged", () => {
    const updater = readRepo("roles/dotfiles/templates/t3code-update.j2");
    const launcher = readRepo("roles/dotfiles/templates/t3code-desktop.j2");
    const desktop = readRepo("roles/dotfiles/files/t3code-nightly.desktop");
    const mimeapps = readRepo("roles/dotfiles/files/mimeapps.list");
    const packages = readRepo("roles/desktop/tasks/main.yml");

    assert.match(updater, /select\(\.prerelease and \(\.tag_name \| contains\("-nightly\."\)\)\)/,
        "the updater must remain pinned to prerelease nightlies");
    assert.ok(launcher.includes(
        'exec "$appimage" --appimage-extract-and-run --password-store=gnome-libsecret "$@"'),
        "the launcher must preserve the callback URL argument");
    assert.match(desktop, /^Exec=\/home\/john\/\.local\/bin\/t3code-desktop %U$/m);
    assert.match(desktop, /^MimeType=x-scheme-handler\/t3code;$/m);
    assert.doesNotMatch(desktop, /x-scheme-handler\/t3code-dev/,
        "nightly is packaged and therefore uses the production scheme");
    assert.match(mimeapps, /^x-scheme-handler\/t3code=t3code-nightly\.desktop$/m);
    assert.doesNotMatch(mimeapps, /^x-scheme-handler\/t3code-dev=/m);
    assert.match(packages, /^\s+- xdg-utils$/m,
        "the upstream Linux callback registration invokes xdg-mime");
    assert.match(packages, /^\s+- fuse-libs$/m,
        "the upstream-generated callback handler starts the AppImage directly");
});
