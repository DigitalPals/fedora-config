#!/usr/bin/env node

// T3 Connect authentication and relay bootstrap for the Quickshell client.
//
// T3 Code Nightly exposes two supported cloud authentication paths. The
// Electron UI uses Clerk's native bridge and returns browser OAuth through
// t3code://app; non-Electron clients use the public CLI OAuth application with
// PKCE and a loopback callback. This panel is not an Electron renderer, so it
// follows the latter path. After the browser callback it reopens the T3 panel,
// discovers the user's linked environments, and performs the same two DPoP
// exchanges as the upstream web client.

import { spawn } from "node:child_process";
import {
    createHash,
    createPrivateKey,
    generateKeyPairSync,
    randomBytes,
    randomUUID,
    sign as signBytes,
} from "node:crypto";
import { promises as fs } from "node:fs";
import { createServer } from "node:http";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const CLOUD_CONFIG = Object.freeze({
    hostedAppUrl: process.env.T3CODE_HOSTED_APP_URL?.trim() || "https://app.t3.codes",
    clerkUrl: process.env.T3CODE_CLERK_URL?.trim() || "https://clerk.t3.codes",
    oauthClientId: process.env.T3CODE_CLERK_CLI_OAUTH_CLIENT_ID?.trim()
        || "hzxSgY2cH10sDU2r",
    relayUrl: process.env.T3CODE_RELAY_URL?.trim() || "https://relay.t3.codes",
    callbackPort: Number(process.env.T3CODE_CLOUD_CALLBACK_PORT || 34338),
});

const RELAY_CLIENT_ID = "t3-web";
const RELAY_CONNECT_SCOPE = "environment:connect";
const STANDARD_ENVIRONMENT_SCOPES = [
    "orchestration:read",
    "orchestration:operate",
    "terminal:operate",
    "review:write",
    "relay:read",
];
const TOKEN_REFRESH_MARGIN_MS = 5 * 60 * 1000;
const ENVIRONMENT_REFRESH_MARGIN_MS = 60 * 1000;
const REQUEST_TIMEOUT_MS = 15_000;
const LOGIN_TIMEOUT_MS = 10 * 60 * 1000;
const P256_ORDER = BigInt("0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551");

const userHome = process.env.HOME || os.homedir();
const stateRoot = process.env.T3CODE_CLOUD_STATE_DIR
    || process.env.XDG_STATE_HOME
    || path.join(userHome, ".local", "state");
const privateStateDir = path.join(stateRoot, "t3code-cloud");
const helperScriptPath = fileURLToPath(import.meta.url);

export const STATE_PATHS = Object.freeze({
    credentials: path.join(privateStateDir, "credentials.json"),
    dpopKey: path.join(privateStateDir, "dpop-key.json"),
    connection: process.env.T3CODE_PANEL_STATE_PATH
        || path.join(stateRoot, "t3code-bar.json"),
});

class HttpError extends Error {
    constructor(message, status) {
        super(message);
        this.name = "HttpError";
        this.status = status;
    }
}

function base64Url(value) {
    return Buffer.from(value).toString("base64url");
}

function sha256(value) {
    return createHash("sha256").update(value).digest();
}

function safeJsonParse(value) {
    try {
        return JSON.parse(value);
    } catch {
        return null;
    }
}

async function readJson(filePath) {
    try {
        return safeJsonParse(await fs.readFile(filePath, "utf8"));
    } catch (error) {
        if (error?.code === "ENOENT")
            return null;
        throw error;
    }
}

async function writePrivateJson(filePath, value) {
    const directory = path.dirname(filePath);
    await fs.mkdir(directory, { recursive: true, mode: 0o700 });
    await fs.chmod(directory, 0o700);
    const temporary = `${filePath}.${process.pid}.${randomUUID()}.tmp`;
    try {
        await fs.writeFile(temporary, JSON.stringify(value, null, 2) + "\n", {
            mode: 0o600,
            flag: "wx",
        });
        await fs.chmod(temporary, 0o600);
        await fs.rename(temporary, filePath);
        await fs.chmod(filePath, 0o600);
    } finally {
        await fs.rm(temporary, { force: true }).catch(() => undefined);
    }
}

function validateServiceOrigin(raw, label) {
    const url = new URL(raw);
    const loopback = url.protocol === "http:"
        && ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname);
    if ((url.protocol !== "https:" && !loopback) || url.username || url.password)
        throw new Error(`${label} must be a secure HTTPS origin.`);
    return url.origin;
}

function safeHttpReason(body) {
    if (!body || typeof body !== "object")
        return "";
    for (const key of ["reason", "code", "error"]) {
        const value = body[key];
        if (typeof value === "string" && /^[a-z0-9._ -]{1,80}$/i.test(value))
            return value;
    }
    return "";
}

async function requestJson(url, options, action) {
    let response;
    try {
        response = await fetch(url, {
            ...options,
            redirect: "error",
            signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
        });
    } catch (error) {
        if (error?.name === "TimeoutError")
            throw new Error(`${action} timed out.`);
        throw new Error(`${action} could not reach T3 Connect.`);
    }
    const text = await response.text();
    const body = text === "" ? {} : safeJsonParse(text);
    if (!response.ok) {
        const reason = safeHttpReason(body);
        throw new HttpError(
            `${action} failed (HTTP ${response.status}${reason ? ` · ${reason}` : ""}).`,
            response.status,
        );
    }
    if (!body || typeof body !== "object")
        throw new Error(`${action} returned an unreadable response.`);
    return body;
}

function formBody(entries) {
    return new URLSearchParams(entries).toString();
}

function decodeIdentity(idToken, fallbackToken = "") {
    for (const token of [idToken, fallbackToken]) {
        if (typeof token !== "string")
            continue;
        const payload = token.split(".")[1];
        if (!payload)
            continue;
        const claims = safeJsonParse(Buffer.from(payload, "base64url").toString("utf8"));
        if (!claims || typeof claims !== "object")
            continue;
        for (const key of ["email", "preferred_username", "sub"]) {
            if (typeof claims[key] === "string" && claims[key].trim() !== "")
                return claims[key].trim();
        }
    }
    return "";
}

function normalizeTokenResponse(response, previousIdentity = "") {
    if (typeof response.access_token !== "string" || response.access_token === ""
            || typeof response.expires_in !== "number")
        throw new Error("T3 Connect returned an invalid OAuth token response.");
    return {
        accessToken: response.access_token,
        refreshToken: typeof response.refresh_token === "string"
            ? response.refresh_token : "",
        expiresAtEpochMs: Date.now() + response.expires_in * 1000,
        identity: decodeIdentity(response.id_token, response.access_token) || previousIdentity,
    };
}

async function exchangeClerkToken(parameters, previousIdentity = "") {
    const clerk = validateServiceOrigin(CLOUD_CONFIG.clerkUrl, "Clerk URL");
    const response = await requestJson(`${clerk}/oauth/token`, {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: formBody(parameters),
    }, "T3 Connect sign-in");
    return normalizeTokenResponse(response, previousIdentity);
}

async function refreshCredentials(credentials) {
    if (credentials?.accessToken
            && Number(credentials.expiresAtEpochMs) > Date.now() + TOKEN_REFRESH_MARGIN_MS)
        return credentials;
    if (!credentials?.refreshToken)
        throw new Error("T3 Connect sign-in is required.");
    const refreshed = await exchangeClerkToken({
        grant_type: "refresh_token",
        refresh_token: credentials.refreshToken,
        client_id: CLOUD_CONFIG.oauthClientId,
    }, credentials.identity || "");
    if (refreshed.refreshToken === "")
        refreshed.refreshToken = credentials.refreshToken;
    await writePrivateJson(STATE_PATHS.credentials, refreshed);
    return refreshed;
}

function buildAuthorizeUrl(state, challenge) {
    const hosted = validateServiceOrigin(CLOUD_CONFIG.hostedAppUrl, "Hosted app URL");
    const url = new URL("/connect", hosted);
    url.hash = new URLSearchParams({
        state,
        challenge,
        port: String(CLOUD_CONFIG.callbackPort),
    }).toString();
    return url.toString();
}

function hostedCallbackUri() {
    return new URL("/connect/callback",
        validateServiceOrigin(CLOUD_CONFIG.hostedAppUrl, "Hosted app URL")).toString();
}

export function parseConnectAuthCode(candidate, expectedState) {
    if (typeof candidate !== "string" || candidate.length > 4096)
        return null;
    const value = candidate.trim();
    const separator = value.lastIndexOf(".");
    if (separator <= 0 || separator === value.length - 1)
        return null;
    const code = value.slice(0, separator);
    const state = value.slice(separator + 1);
    if (state !== expectedState || !/^[A-Za-z0-9_-]+$/.test(code))
        return null;
    return code;
}

function completionPage() {
    return `<!doctype html><meta charset="utf-8"><title>T3 Connect sign-in complete</title>
<style>body{font:16px system-ui;color:#eee;background:#17171d;display:grid;place-items:center;height:100vh;margin:0}main{text-align:center;max-width:32rem}h1{font-size:1.35rem}</style>
<main><h1>T3 Connect sign-in complete</h1><p>You can close this tab. The T3 Code panel will reopen automatically.</p></main>`;
}

function openExternal(url) {
    return new Promise((resolve, reject) => {
        const child = spawn("xdg-open", [url], { detached: true, stdio: "ignore" });
        child.once("error", () => reject(new Error("Could not open the T3 Connect sign-in page.")));
        child.once("spawn", () => {
            child.unref();
            resolve();
        });
    });
}

function watchClipboardAuthorization(expectedState) {
    let watcher;
    let stop = () => undefined;
    const authorization = new Promise(resolve => {
        // app.t3.codes may lag the Nightly client and fall back to its hosted
        // terminal handoff. While this explicitly initiated login is pending,
        // accept only a copied T3 code whose embedded state equals this
        // process's fresh random state. All unrelated clipboard data is
        // discarded by the short-lived filter subprocess.
        watcher = spawn("wl-paste", [
            "--type", "text", "--watch",
            process.execPath,
            helperScriptPath,
            "clipboard-code",
            expectedState,
        ], { stdio: ["ignore", "pipe", "ignore"] });
        let output = "";
        watcher.stdout?.setEncoding("utf8");
        watcher.stdout?.on("data", chunk => {
            output += chunk;
            const newline = output.indexOf("\n");
            if (newline < 0)
                return;
            const code = output.slice(0, newline).trim();
            if (code !== "")
                resolve(code);
        });
        watcher.once("error", () => undefined);
        stop = () => {
            if (watcher && watcher.exitCode === null)
                watcher.kill();
        };
    });
    return { authorization, stop: () => stop() };
}

async function readStdin(maxBytes) {
    const chunks = [];
    let size = 0;
    for await (const chunk of process.stdin) {
        size += chunk.length;
        if (size > maxBytes)
            return "";
        chunks.push(chunk);
    }
    return Buffer.concat(chunks).toString("utf8");
}

function activatePanel() {
    try {
        const child = spawn("qs", ["ipc", "call", "popouts", "open", "t3code"], {
            detached: true,
            stdio: "ignore",
        });
        child.once("error", () => undefined);
        child.unref();
    } catch {
        // Authentication is complete even when no running shell can be found.
    }
}

export async function interactiveLogin() {
    if (!Number.isInteger(CLOUD_CONFIG.callbackPort)
            || CLOUD_CONFIG.callbackPort < 1 || CLOUD_CONFIG.callbackPort > 65535)
        throw new Error("The T3 Connect callback port is invalid.");

    const verifier = base64Url(randomBytes(32));
    const challenge = base64Url(sha256(verifier));
    const state = base64Url(randomBytes(16));
    const redirectUri = `http://127.0.0.1:${CLOUD_CONFIG.callbackPort}/callback`;
    let finish;
    let fail;
    const callback = new Promise((resolve, reject) => {
        finish = resolve;
        fail = reject;
    });
    const server = createServer((request, response) => {
        const url = new URL(request.url || "/", redirectUri);
        const code = url.searchParams.get("code") || "";
        if (url.pathname !== "/callback" || url.searchParams.get("state") !== state || !code) {
            response.writeHead(400, { "content-type": "text/plain; charset=utf-8" });
            response.end("Invalid T3 Connect authorization callback.");
            return;
        }
        response.writeHead(200, {
            "content-type": "text/html; charset=utf-8",
            "cache-control": "no-store",
        });
        response.end(completionPage());
        finish(code);
    });
    await new Promise((resolve, reject) => {
        server.once("listening", resolve);
        server.once("error", reject);
        server.listen(CLOUD_CONFIG.callbackPort, "127.0.0.1");
    }).catch(error => {
        if (error?.code === "EADDRINUSE")
            throw new Error("Another T3 Connect sign-in is already running.");
        throw new Error("Could not start the local T3 Connect callback.");
    });
    server.on("error", () => fail(new Error("The local T3 Connect callback stopped.")));

    let timer;
    const clipboard = watchClipboardAuthorization(state);
    try {
        await openExternal(buildAuthorizeUrl(state, challenge));
        const authorization = await Promise.race([
            callback.then(code => ({ code, redirectUri })),
            clipboard.authorization.then(code => ({ code, redirectUri: hostedCallbackUri() })),
            new Promise((_, reject) => {
                timer = setTimeout(() => reject(new Error("T3 Connect sign-in timed out.")),
                    LOGIN_TIMEOUT_MS);
            }),
        ]);
        const credentials = await exchangeClerkToken({
            grant_type: "authorization_code",
            code: authorization.code,
            redirect_uri: authorization.redirectUri,
            client_id: CLOUD_CONFIG.oauthClientId,
            code_verifier: verifier,
        });
        await writePrivateJson(STATE_PATHS.credentials, credentials);
        return credentials;
    } finally {
        clearTimeout(timer);
        clipboard.stop();
        await new Promise(resolve => server.close(resolve));
    }
}

function publicJwkFrom(privateJwk) {
    return {
        kty: privateJwk.kty,
        crv: privateJwk.crv,
        x: privateJwk.x,
        y: privateJwk.y,
    };
}

export function computeDpopThumbprint(publicJwk) {
    const canonical = JSON.stringify({
        crv: publicJwk.crv,
        kty: publicJwk.kty,
        x: publicJwk.x,
        y: publicJwk.y,
    });
    return base64Url(sha256(canonical));
}

async function loadOrCreateDpopKey() {
    const stored = await readJson(STATE_PATHS.dpopKey);
    if (stored?.privateJwk && stored?.publicJwk) {
        const thumbprint = computeDpopThumbprint(stored.publicJwk);
        if (thumbprint === stored.thumbprint) {
            return {
                ...stored,
                privateKey: createPrivateKey({ key: stored.privateJwk, format: "jwk" }),
            };
        }
    }
    const generated = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
    const privateJwk = generated.privateKey.export({ format: "jwk" });
    const publicJwk = publicJwkFrom(privateJwk);
    const persisted = {
        privateJwk,
        publicJwk,
        thumbprint: computeDpopThumbprint(publicJwk),
    };
    await writePrivateJson(STATE_PATHS.dpopKey, persisted);
    return { ...persisted, privateKey: generated.privateKey };
}

function normalizedProofUrl(raw) {
    const url = new URL(raw);
    url.search = "";
    url.hash = "";
    return url.toString();
}

function normalizeP256LowS(signature) {
    // @noble/curves, used by the T3 server verifier, rejects malleable high-S
    // ECDSA signatures. OpenSSL may emit either form, so canonicalize the
    // 64-byte JOSE r||s value before putting it in the compact JWT.
    const s = BigInt(`0x${signature.subarray(32).toString("hex")}`);
    if (s <= P256_ORDER / 2n)
        return signature;
    const normalized = Buffer.from(signature);
    Buffer.from((P256_ORDER - s).toString(16).padStart(64, "0"), "hex").copy(normalized, 32);
    return normalized;
}

export function createDpopProof({ method, url, accessToken = "", key, now = Date.now() }) {
    const header = base64Url(JSON.stringify({
        typ: "dpop+jwt",
        alg: "ES256",
        jwk: key.publicJwk,
    }));
    const payload = {
        htm: method.toUpperCase(),
        htu: normalizedProofUrl(url),
        jti: randomUUID(),
        iat: Math.floor(now / 1000),
        ...(accessToken ? { ath: base64Url(sha256(accessToken)) } : {}),
    };
    const encodedPayload = base64Url(JSON.stringify(payload));
    const signingInput = `${header}.${encodedPayload}`;
    const signature = normalizeP256LowS(signBytes("sha256", Buffer.from(signingInput), {
        key: key.privateKey,
        dsaEncoding: "ieee-p1363",
    }));
    return `${signingInput}.${base64Url(signature)}`;
}

async function relayAccessToken(credentials, key, scopes) {
    const relay = validateServiceOrigin(CLOUD_CONFIG.relayUrl, "Relay URL");
    const url = `${relay}/v1/client/dpop-token`;
    const response = await requestJson(url, {
        method: "POST",
        headers: {
            "content-type": "application/x-www-form-urlencoded",
            dpop: createDpopProof({ method: "POST", url, key }),
        },
        body: formBody({
            grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
            subject_token: credentials.accessToken,
            subject_token_type: "urn:ietf:params:oauth:token-type:jwt",
            requested_token_type: "urn:ietf:params:oauth:token-type:access_token",
            resource: relay,
            scope: scopes.join(" "),
            client_id: RELAY_CLIENT_ID,
        }),
    }, "T3 Connect relay authorization");
    if (typeof response.access_token !== "string" || response.token_type !== "DPoP")
        throw new Error("T3 Connect returned an invalid relay token.");
    return response.access_token;
}

async function linkedEnvironments(credentials) {
    const relay = validateServiceOrigin(CLOUD_CONFIG.relayUrl, "Relay URL");
    const response = await requestJson(`${relay}/v1/environments`, {
        method: "GET",
        headers: { authorization: `Bearer ${credentials.accessToken}` },
    }, "T3 Connect environment discovery");
    return Array.isArray(response.environments) ? response.environments : [];
}

async function preferredEnvironmentId(previousState, environments) {
    if (typeof previousState?.environmentId === "string"
            && environments.some(item => item.environmentId === previousState.environmentId))
        return previousState.environmentId;
    try {
        const localId = (await fs.readFile(path.join(userHome, ".t3", "userdata",
            "environment-id"), "utf8")).trim();
        if (environments.some(item => item.environmentId === localId))
            return localId;
    } catch {
        // A remote-only client has no local environment id.
    }
    return environments.toSorted((left, right) =>
        String(right.linkedAt || "").localeCompare(String(left.linkedAt || "")))[0]?.environmentId
        || "";
}

function checkedEndpoint(endpoint) {
    if (!endpoint || typeof endpoint !== "object")
        throw new Error("T3 Connect returned no managed environment endpoint.");
    return {
        httpBaseUrl: validateServiceOrigin(endpoint.httpBaseUrl, "Environment HTTP URL"),
        wsBaseUrl: (() => {
            const url = new URL(endpoint.wsBaseUrl);
            const loopback = url.protocol === "ws:"
                && ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname);
            if ((url.protocol !== "wss:" && !loopback) || url.username || url.password)
                throw new Error("Environment WebSocket URL must be secure.");
            return url.toString().replace(/\/$/, "");
        })(),
        providerKind: typeof endpoint.providerKind === "string" ? endpoint.providerKind : "",
    };
}

async function exchangeEnvironmentToken(endpoint, bootstrapCredential, key) {
    const url = `${endpoint.httpBaseUrl}/oauth/token`;
    const response = await requestJson(url, {
        method: "POST",
        headers: {
            "content-type": "application/x-www-form-urlencoded",
            dpop: createDpopProof({ method: "POST", url, key }),
        },
        body: formBody({
            grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
            subject_token: bootstrapCredential,
            subject_token_type: "urn:t3:params:oauth:token-type:environment-bootstrap",
            requested_token_type: "urn:ietf:params:oauth:token-type:access_token",
            scope: STANDARD_ENVIRONMENT_SCOPES.join(" "),
            client_label: "Quickshell T3 panel",
            client_device_type: "desktop",
            client_os: "linux",
        }),
    }, "T3 Connect environment authorization");
    if (typeof response.access_token !== "string" || response.token_type !== "DPoP"
            || typeof response.expires_in !== "number")
        throw new Error("T3 Connect returned an invalid environment token.");
    return response;
}

export async function connectCloud(credentials) {
    const currentCredentials = await refreshCredentials(credentials);
    const environments = await linkedEnvironments(currentCredentials);
    const previousState = await readJson(STATE_PATHS.connection);
    if (environments.length === 0) {
        const state = {
            authMode: "cloud",
            cloudStatus: "no-environments",
            cloudIdentity: currentCredentials.identity || "signed in",
            environmentCandidates: [],
        };
        await writePrivateJson(STATE_PATHS.connection, state);
        return state;
    }

    const environmentId = await preferredEnvironmentId(previousState, environments);
    const environment = environments.find(item => item.environmentId === environmentId);
    if (!environment)
        throw new Error("T3 Connect could not select a linked environment.");

    const key = await loadOrCreateDpopKey();
    const relayToken = await relayAccessToken(currentCredentials, key, [RELAY_CONNECT_SCOPE]);
    const relay = validateServiceOrigin(CLOUD_CONFIG.relayUrl, "Relay URL");
    const connectUrl = `${relay}/v1/environments/${encodeURIComponent(environmentId)}/connect`;
    const connected = await requestJson(connectUrl, {
        method: "POST",
        headers: {
            authorization: `DPoP ${relayToken}`,
            dpop: createDpopProof({
                method: "POST",
                url: connectUrl,
                accessToken: relayToken,
                key,
            }),
            "content-type": "application/json",
        },
        body: JSON.stringify({ clientKeyThumbprint: key.thumbprint }),
    }, "T3 Connect environment connection");
    if (connected.environmentId !== environmentId || typeof connected.credential !== "string")
        throw new Error("T3 Connect returned an invalid environment connection.");

    const endpoint = checkedEndpoint(connected.endpoint || environment.endpoint);
    const environmentToken = await exchangeEnvironmentToken(endpoint, connected.credential, key);
    const state = {
        authMode: "cloud",
        cloudStatus: "connected",
        cloudIdentity: currentCredentials.identity || "signed in",
        environmentId,
        environmentLabel: typeof environment.label === "string" ? environment.label : "T3 Connect",
        httpBaseUrl: endpoint.httpBaseUrl,
        wsBaseUrl: endpoint.wsBaseUrl,
        accessToken: environmentToken.access_token,
        tokenType: "DPoP",
        expiresAtEpochMs: Date.now() + environmentToken.expires_in * 1000,
        scope: typeof environmentToken.scope === "string"
            ? environmentToken.scope : STANDARD_ENVIRONMENT_SCOPES.join(" "),
    };
    await writePrivateJson(STATE_PATHS.connection, state);
    return state;
}

async function usableConnection() {
    const current = await readJson(STATE_PATHS.connection);
    if (current?.authMode === "cloud" && current?.tokenType === "DPoP"
            && current?.accessToken && current?.httpBaseUrl && current?.wsBaseUrl
            && Number(current.expiresAtEpochMs) > Date.now() + ENVIRONMENT_REFRESH_MARGIN_MS)
        return current;
    const credentials = await refreshCredentials(await readJson(STATE_PATHS.credentials));
    const connected = await connectCloud(credentials);
    if (!connected.accessToken)
        throw new Error("No environments are linked to this T3 Connect account.");
    return connected;
}

async function requestWebSocketTicket(connection, key) {
    const url = `${connection.httpBaseUrl}/api/auth/websocket-ticket`;
    return requestJson(url, {
        method: "POST",
        headers: {
            authorization: `DPoP ${connection.accessToken}`,
            dpop: createDpopProof({
                method: "POST",
                url,
                accessToken: connection.accessToken,
                key,
            }),
        },
    }, "T3 Connect WebSocket authorization");
}

export async function issueWebSocketTicket() {
    let connection = await usableConnection();
    const key = await loadOrCreateDpopKey();
    let issued;
    try {
        issued = await requestWebSocketTicket(connection, key);
    } catch (error) {
        if (!(error instanceof HttpError) || ![401, 403].includes(error.status))
            throw error;
        const credentials = await refreshCredentials(await readJson(STATE_PATHS.credentials));
        connection = await connectCloud(credentials);
        issued = await requestWebSocketTicket(connection, key);
    }
    if (typeof issued.ticket !== "string" || issued.ticket === "")
        throw new Error("T3 Connect returned no WebSocket ticket.");
    const socketUrl = new URL(connection.wsBaseUrl);
    if (socketUrl.pathname === "" || socketUrl.pathname === "/")
        socketUrl.pathname = "/ws";
    socketUrl.searchParams.set("wsTicket", issued.ticket);
    return { socketUrl: socketUrl.toString() };
}

async function cloudStatus() {
    const credentials = await readJson(STATE_PATHS.credentials);
    const connection = await readJson(STATE_PATHS.connection);
    return {
        signedIn: Boolean(credentials?.accessToken || credentials?.refreshToken),
        identity: credentials?.identity || connection?.cloudIdentity || "",
        status: connection?.cloudStatus || "signed-out",
        environmentId: connection?.environmentId || "",
        environmentLabel: connection?.environmentLabel || "",
    };
}

async function removeCloudState() {
    await Promise.all([
        fs.rm(STATE_PATHS.credentials, { force: true }),
        fs.rm(STATE_PATHS.dpopKey, { force: true }),
        fs.rm(STATE_PATHS.connection, { force: true }),
    ]);
}

async function loginAndConnect() {
    try {
        let credentials = await readJson(STATE_PATHS.credentials);
        try {
            credentials = await refreshCredentials(credentials);
        } catch {
            credentials = await interactiveLogin();
        }
        const result = await connectCloud(credentials);
        return {
            status: result.cloudStatus,
            identity: result.cloudIdentity,
            environmentId: result.environmentId || "",
            environmentLabel: result.environmentLabel || "",
        };
    } finally {
        // Browser sign-in steals focus. Return to the module on success and on
        // post-callback failures so the result never disappears behind it.
        activatePanel();
    }
}

async function main(argv) {
    const command = argv[2] || "status";
    if (command === "clipboard-code") {
        const code = parseConnectAuthCode(await readStdin(4096), argv[3] || "");
        if (code !== null)
            process.stdout.write(code + "\n");
        return;
    }
    let result;
    if (command === "login")
        result = await loginAndConnect();
    else if (command === "connect") {
        const connected = await connectCloud(await readJson(STATE_PATHS.credentials));
        result = {
            status: connected.cloudStatus,
            identity: connected.cloudIdentity,
            environmentId: connected.environmentId || "",
            environmentLabel: connected.environmentLabel || "",
        };
    }
    else if (command === "ticket")
        result = await issueWebSocketTicket();
    else if (command === "status")
        result = await cloudStatus();
    else if (command === "logout") {
        await removeCloudState();
        result = { status: "signed-out" };
    } else {
        throw new Error("Usage: t3-cloud.mjs [login|connect|ticket|status|logout]");
    }
    process.stdout.write(JSON.stringify(result) + "\n");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
    main(process.argv).catch(error => {
        process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
        process.exitCode = 1;
    });
}
