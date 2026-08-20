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
    assert.match(helper, /qs", \["ipc", "call", "popouts", "open", "t3code"\]/);
    assert.match(helper, /tokens\/t3-relay/);
    assert.match(helper, /Continue with Google/);
    assert.match(helper, /Continue with GitHub/);
    assert.match(helper, /browserCommand:[^\n]+"xdg-open"/);
    assert.doesNotMatch(helper, /secret-tool|desktopCommand|openT3Code/);
});

test("the T3 Connect helper emits verifiable T3-compatible DPoP proofs", async () => {
    const script = path.join(shellDir, "scripts/t3-cloud.mjs");
    const helper = await import(pathToFileURL(script).href + `?dpop=${Date.now()}`);
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

test("the T3 Connect browser flow authorizes and tickets a linked environment", async t => {
    const requests = [];
    let signedIn = false;
    const activeSession = {
        id: "session-browser",
        status: "active",
        user: {
            primary_email_address_id: "email-browser",
            email_addresses: [{
                id: "email-browser",
                email_address: "browser@example.test",
            }],
        },
    };
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
            const address = server.address();
            const base = `http://127.0.0.1:${address.port}`;
            const parsed = new URL(request.url, base);
            const route = parsed.pathname;
            const clerkHeaders = route.startsWith("/v1/client")
                ? { authorization: "Bearer clerk-native-client-token" } : {};
            const json = value => {
                response.writeHead(200, {
                    "content-type": "application/json",
                    ...clerkHeaders,
                });
                response.end(JSON.stringify(value));
            };
            if (request.method === "GET" && route === "/v1/client") {
                json({
                    response: {
                        object: "client",
                        sessions: signedIn ? [activeSession] : [],
                        last_active_session_id: signedIn ? activeSession.id : null,
                    },
                    client: null,
                });
            } else if (request.method === "POST" && route === "/v1/client/sign_ins") {
                json({
                    response: {
                        id: "sign-in-browser",
                        status: "needs_identifier",
                        created_session_id: null,
                        first_factor_verification: {
                            status: "unverified",
                            strategy: "oauth_google",
                            external_verification_redirect_url:
                                "https://accounts.example.test/t3-connect",
                        },
                    },
                    client: null,
                });
            } else if (request.method === "GET"
                    && route === "/v1/client/sign_ins/sign-in-browser") {
                signedIn = true;
                json({
                    response: {
                        id: "sign-in-browser",
                        status: "complete",
                        created_session_id: activeSession.id,
                    },
                    client: {
                        object: "client",
                        sessions: [activeSession],
                        last_active_session_id: activeSession.id,
                    },
                });
            } else if (request.method === "POST"
                    && route === "/v1/client/sessions/session-browser/tokens/t3-relay") {
                json({ response: { jwt: "relay-clerk-template-token" }, client: null });
            } else if (request.method === "GET" && route === "/v1/environments") {
                json({ environments: [{
                    environmentId: "env-browser",
                    label: "Linked workstation",
                    endpoint: {
                        httpBaseUrl: base,
                        wsBaseUrl: base.replace("http:", "ws:"),
                        providerKind: "cloudflare",
                    },
                    linkedAt: "2026-08-19T18:00:00.000Z",
                }] });
            } else if (request.method === "POST" && route === "/v1/client/dpop-token") {
                json({
                    access_token: "relay-access-token",
                    issued_token_type: "urn:ietf:params:oauth:token-type:access_token",
                    token_type: "DPoP",
                    expires_in: 300,
                    scope: "environment:connect",
                });
            } else if (request.method === "POST"
                    && route === "/v1/environments/env-browser/connect") {
                json({
                    environmentId: "env-browser",
                    endpoint: {
                        httpBaseUrl: base,
                        wsBaseUrl: base.replace("http:", "ws:"),
                        providerKind: "cloudflare",
                    },
                    credential: "environment-bootstrap",
                    expiresAt: "2026-08-19T22:00:00.000Z",
                });
            } else if (request.method === "POST" && route === "/oauth/token") {
                json({
                    access_token: "environment-access-token",
                    issued_token_type: "urn:ietf:params:oauth:token-type:access_token",
                    token_type: "DPoP",
                    expires_in: 3600,
                    scope: "orchestration:read orchestration:operate terminal:operate review:write relay:read",
                });
            } else if (request.method === "POST"
                    && route === "/api/auth/websocket-ticket") {
                json({ ticket: "short-lived-ticket" });
            } else {
                response.writeHead(404, { "content-type": "application/json" });
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
    const binDir = path.join(temporaryHome, "bin");
    const browserOpened = path.join(temporaryHome, "browser-opened.json");
    const mimeCalled = path.join(temporaryHome, "mime-called");
    const browserCommand = path.join(binDir, "open-browser");
    const mimeCommand = path.join(binDir, "xdg-mime");
    fs.mkdirSync(binDir);
    fs.writeFileSync(browserCommand, `#!/usr/bin/env node
const fs = require("node:fs");
const net = require("node:net");
const { spawnSync } = require("node:child_process");
(async () => {
    const landing = process.argv[2];
    const local = new URL(landing);
    const speculativeSocket = net.connect(Number(local.port), local.hostname);
    await new Promise((resolve, reject) => {
        speculativeSocket.once("connect", resolve);
        speculativeSocket.once("error", reject);
    });
    const started = await fetch(new URL("/start?provider=google", landing), {
        redirect: "manual",
    });
    fs.writeFileSync(process.env.T3_TEST_BROWSER_OPENED, JSON.stringify({
        landing,
        providerRedirect: started.headers.get("location"),
    }));
    if (started.status !== 302)
        process.exit(2);
    const callback = spawnSync(process.execPath, [
        process.env.T3_TEST_HELPER,
        "oauth-callback",
        "t3code://app/?rotating_token_nonce=test-nonce",
    ], { env: process.env, encoding: "utf8" });
    if (callback.status !== 0)
        process.exit(callback.status || 3);
    await new Promise(resolve => speculativeSocket.once("close", resolve));
})().catch(() => process.exit(4));
`, { mode: 0o755 });
    fs.writeFileSync(mimeCommand, `#!/usr/bin/env node
require("node:fs").writeFileSync(
    process.env.T3_TEST_MIME_CALLED,
    process.argv.slice(2).join(" "),
);
`, { mode: 0o755 });
    fs.writeFileSync(path.join(binDir, "qs"), "#!/usr/bin/env node\n", { mode: 0o755 });

    const script = path.join(shellDir, "scripts/t3-cloud.mjs");
    const env = {
        ...process.env,
        HOME: temporaryHome,
        PATH: `${binDir}:${process.env.PATH}`,
        T3_TEST_BROWSER_OPENED: browserOpened,
        T3_TEST_HELPER: script,
        T3_TEST_MIME_CALLED: mimeCalled,
        T3CODE_CLOUD_STATE_DIR: stateRoot,
        T3CODE_CLERK_URL: backend,
        T3CODE_RELAY_URL: backend,
        T3CODE_BROWSER_COMMAND: browserCommand,
        T3CODE_MIME_COMMAND: mimeCommand,
    };
    const connected = await runNode(script, "login", env);
    assert.equal(connected.status, 0, connected.stderr);
    assert.equal(connected.stderr, "");
    assert.deepEqual(JSON.parse(connected.stdout), {
        status: "connected",
        identity: "browser@example.test",
        environmentId: "env-browser",
        environmentLabel: "Linked workstation",
    });
    assert.doesNotMatch(connected.stdout,
        /clerk-native-client-token|relay-clerk-template-token|relay-access-token|environment-access-token|environment-bootstrap/);
    const opened = JSON.parse(fs.readFileSync(browserOpened, "utf8"));
    assert.match(opened.landing, /^http:\/\/127\.0\.0\.1:\d+\/$/);
    assert.equal(opened.providerRedirect, "https://accounts.example.test/t3-connect");
    assert.equal(fs.readFileSync(mimeCalled, "utf8"),
        "default t3code-nightly.desktop x-scheme-handler/t3code");

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
        cloudIdentity: "browser@example.test",
        environmentId: "env-browser",
        environmentLabel: "Linked workstation",
        httpBaseUrl: backend,
        wsBaseUrl: backend.replace("http:", "ws:"),
        accessToken: "environment-access-token",
        tokenType: "DPoP",
    });
    assert.equal(fs.statSync(statePath).mode & 0o777, 0o600);
    assert.equal(fs.statSync(path.join(privateState, "clerk-client.json")).mode & 0o777, 0o600);
    assert.equal(fs.statSync(path.join(privateState, "dpop-key.json")).mode & 0o777, 0o600);
    assert.equal(fs.existsSync(path.join(privateState, "browser-login.json")), false);

    const initialClient = requests.find(item => item.method === "GET"
        && new URL(item.url, backend).pathname === "/v1/client");
    assert.equal(initialClient.headers.authorization, undefined,
        "the panel must create its own Clerk client instead of reading Nightly's session");
    const clerkSignIn = requests.find(item => item.method === "POST"
        && new URL(item.url, backend).pathname === "/v1/client/sign_ins");
    assert.equal(clerkSignIn.headers.authorization, "Bearer clerk-native-client-token");
    assert.equal(clerkSignIn.headers["content-type"], "application/x-www-form-urlencoded");
    assert.deepEqual(Object.fromEntries(new URLSearchParams(clerkSignIn.body)), {
        strategy: "oauth_google",
        redirect_url: "t3code://app/",
        action_complete_redirect_url: "t3code://app/",
    });
    const clerkCallback = requests.find(item =>
        new URL(item.url, backend).pathname === "/v1/client/sign_ins/sign-in-browser");
    assert.equal(new URL(clerkCallback.url, backend).searchParams.get("rotating_token_nonce"),
        "test-nonce");
    for (const clerkRequest of requests.filter(item => {
        const route = new URL(item.url, backend).pathname;
        return route !== "/v1/client/dpop-token"
            && (route === "/v1/client" || route.startsWith("/v1/client/"));
    })) {
        const params = new URL(clerkRequest.url, backend).searchParams;
        assert.equal(params.get("__clerk_api_version"), "2026-05-12");
        assert.equal(params.get("_clerk_js_version"), "6.29.2");
        assert.equal(params.get("_is_native"), "1");
    }

    const listed = requests.find(item => item.url === "/v1/environments");
    assert.equal(listed.headers.authorization, "Bearer relay-clerk-template-token");
    const clerkTemplate = requests.find(item =>
        new URL(item.url, backend).pathname
            === "/v1/client/sessions/session-browser/tokens/t3-relay");
    assert.equal(clerkTemplate.headers.authorization, "Bearer clerk-native-client-token");
    const relayExchange = requests.find(item => item.url === "/v1/client/dpop-token");
    assert.match(relayExchange.headers.dpop, /^[^.]+\.[^.]+\.[^.]+$/);
    const relayForm = new URLSearchParams(relayExchange.body);
    assert.equal(relayForm.get("client_id"), "t3-web");
    assert.equal(relayForm.get("scope"), "environment:connect");
    assert.equal(relayForm.get("subject_token"), "relay-clerk-template-token");
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

test("the nightly launcher routes pending panel callbacks and preserves its fallback", () => {
    const updater = readRepo("roles/dotfiles/templates/t3code-update.j2");
    const launcher = readRepo("roles/dotfiles/templates/t3code-desktop.j2");
    const desktop = readRepo("roles/dotfiles/files/t3code-nightly.desktop");
    const mimeapps = readRepo("roles/dotfiles/files/mimeapps.list");
    const packages = readRepo("roles/desktop/tasks/main.yml");

    assert.match(updater, /select\(\.prerelease and \(\.tag_name \| contains\("-nightly\."\)\)\)/,
        "the updater must remain pinned to prerelease nightlies");
    assert.ok(launcher.includes(
        'exec "$appimage" --appimage-extract-and-run --password-store=gnome-libsecret "$@"'),
        "the launcher must preserve non-panel callback URL arguments");
    assert.match(launcher, /oauth-callback "\$1"/,
        "a pending browser sign-in must return to the panel instead of opening Nightly");
    assert.match(launcher, /\[\[ \$\{1-\} == t3code:\/\/app\/\* \]\]/);
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
