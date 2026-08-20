#!/usr/bin/env node

// T3 Connect authentication and relay bootstrap for the Quickshell client.
//
// Relay access requires the `t3-relay` Clerk JWT template used by T3 Code
// Nightly. The public CLI OAuth token can manage linked environments but is not
// accepted by the relay DPoP exchange. This helper therefore reuses Nightly's
// native Clerk session, asks Clerk for the relay template JWT, then performs the
// same two DPoP exchanges as the upstream web client.

import { spawn } from "node:child_process";
import {
    createDecipheriv,
    createHash,
    createPrivateKey,
    generateKeyPairSync,
    pbkdf2Sync,
    randomUUID,
    sign as signBytes,
} from "node:crypto";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

export const CLOUD_CONFIG = Object.freeze({
    clerkUrl: process.env.T3CODE_CLERK_URL?.trim() || "https://clerk.t3.codes",
    relayUrl: process.env.T3CODE_RELAY_URL?.trim() || "https://relay.t3.codes",
    desktopCommand: process.env.T3CODE_DESKTOP_COMMAND?.trim() || "t3code-desktop",
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
const ENVIRONMENT_REFRESH_MARGIN_MS = 60 * 1000;
const REQUEST_TIMEOUT_MS = 15_000;
const LOGIN_TIMEOUT_MS = 10 * 60 * 1000;
const SIGN_IN_POLL_MS = Number(process.env.T3CODE_SIGN_IN_POLL_MS || 1000);
const CLERK_NATIVE_ELECTRON_VERSION = "0.0.33";
const P256_ORDER = BigInt("0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551");

const userHome = process.env.HOME || os.homedir();
const stateRoot = process.env.T3CODE_CLOUD_STATE_DIR
    || process.env.XDG_STATE_HOME
    || path.join(userHome, ".local", "state");
const privateStateDir = path.join(stateRoot, "t3code-cloud");
const t3CodeClerkTokenPath = process.env.T3CODE_CLERK_TOKEN_PATH
    || path.join(userHome, ".t3", "userdata", "clerk-tokens.json");

export const STATE_PATHS = Object.freeze({
    legacyCredentials: path.join(privateStateDir, "credentials.json"),
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

function collectCommandOutput(command, args, action, maxBytes = 4096) {
    return new Promise((resolve, reject) => {
        const child = spawn(command, args, { stdio: ["ignore", "pipe", "ignore"] });
        let output = "";
        child.stdout?.setEncoding("utf8");
        child.stdout?.on("data", chunk => {
            output += chunk;
            if (output.length > maxBytes)
                child.kill();
        });
        child.once("error", () => reject(new Error(`${action} is unavailable.`)));
        child.once("close", status => {
            if (status !== 0 || output === "" || output.length > maxBytes)
                reject(new Error(`${action} failed.`));
            else
                resolve(output);
        });
    });
}

async function readT3CodeClientToken() {
    const stored = await readJson(t3CodeClerkTokenPath);
    const value = stored?.__clerk_client_jwt;
    if (typeof value !== "string" || value === "")
        return "";
    if (value.startsWith("raw:"))
        return value.slice("raw:".length);
    if (!value.startsWith("enc:"))
        throw new Error("T3 Code's saved sign-in has an unsupported format.");

    const encrypted = Buffer.from(value.slice("enc:".length), "base64");
    if (encrypted.subarray(0, 3).toString("ascii") !== "v11")
        throw new Error("T3 Code's encrypted sign-in has an unsupported format.");
    const password = (await collectCommandOutput(
        "secret-tool",
        ["lookup", "application", "t3code"],
        "T3 Code secure storage",
    )).trimEnd();
    try {
        const key = pbkdf2Sync(password, "saltysalt", 1, 16, "sha1");
        const decipher = createDecipheriv("aes-128-cbc", key, Buffer.alloc(16, " "));
        return Buffer.concat([
            decipher.update(encrypted.subarray(3)),
            decipher.final(),
        ]).toString("utf8");
    } catch {
        throw new Error("T3 Code's saved sign-in could not be unlocked.");
    }
}

async function clerkNativeRequest(resource, clientToken, options, action) {
    const clerk = validateServiceOrigin(CLOUD_CONFIG.clerkUrl, "Clerk URL");
    const url = new URL(resource, `${clerk}/`);
    url.searchParams.set("_is_native", "1");
    url.searchParams.set("_electron_sdk_version", CLERK_NATIVE_ELECTRON_VERSION);
    let response;
    try {
        response = await fetch(url, {
            ...options,
            headers: {
                authorization: `Bearer ${clientToken}`,
                "content-type": "application/json",
                ...options?.headers,
            },
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
        const responseBody = body?.response && typeof body.response === "object"
            ? body.response : body;
        const reason = safeHttpReason(responseBody);
        throw new HttpError(
            `${action} failed (HTTP ${response.status}${reason ? ` · ${reason}` : ""}).`,
            response.status,
        );
    }
    if (!body || typeof body !== "object")
        throw new Error(`${action} returned an unreadable response.`);
    const authorization = response.headers.get("authorization") || "";
    return {
        data: body.response && typeof body.response === "object" ? body.response : body,
        clientToken: authorization.startsWith("Bearer ")
            ? authorization.slice("Bearer ".length) : authorization || clientToken,
    };
}

function clerkSessionIdentity(session) {
    const user = session?.user;
    if (!user || typeof user !== "object")
        return "";
    const addresses = Array.isArray(user.email_addresses) ? user.email_addresses : [];
    const primary = addresses.find(address => address?.id === user.primary_email_address_id)
        || addresses[0];
    if (typeof primary?.email_address === "string" && primary.email_address.trim() !== "")
        return primary.email_address.trim();
    return typeof user.username === "string" ? user.username.trim() : "";
}

function jwtExpiryEpochMs(token) {
    try {
        const claims = safeJsonParse(Buffer.from(token.split(".")[1], "base64url").toString("utf8"));
        return Number.isFinite(claims?.exp) ? claims.exp * 1000 : Date.now() + 30_000;
    } catch {
        return Date.now() + 30_000;
    }
}

export async function t3CodeRelayCredentials() {
    const initialClientToken = await readT3CodeClientToken();
    if (initialClientToken === "")
        return null;

    let clientResult;
    try {
        clientResult = await clerkNativeRequest(
            "/v1/client",
            initialClientToken,
            { method: "GET" },
            "T3 Code sign-in check",
        );
    } catch (error) {
        if (error instanceof HttpError && [401, 403].includes(error.status))
            return null;
        throw error;
    }
    const sessions = Array.isArray(clientResult.data.sessions)
        ? clientResult.data.sessions : [];
    const activeSession = sessions.find(session =>
        session?.id === clientResult.data.last_active_session_id
            && session?.status === "active")
        || sessions.find(session => session?.status === "active");
    if (!activeSession?.id)
        return null;

    const tokenResult = await clerkNativeRequest(
        `/v1/client/sessions/${encodeURIComponent(activeSession.id)}/tokens/t3-relay?debug=skip_cache`,
        clientResult.clientToken,
        { method: "POST", body: "{}" },
        "T3 Connect relay sign-in",
    );
    if (typeof tokenResult.data.jwt !== "string" || tokenResult.data.jwt === "")
        throw new Error("T3 Code returned no T3 Connect relay credential.");
    return {
        source: "t3code-session",
        accessToken: tokenResult.data.jwt,
        refreshToken: "",
        expiresAtEpochMs: jwtExpiryEpochMs(tokenResult.data.jwt),
        identity: clerkSessionIdentity(activeSession)
            || decodeIdentity("", tokenResult.data.jwt),
    };
}

function openT3Code() {
    return new Promise((resolve, reject) => {
        const child = spawn(CLOUD_CONFIG.desktopCommand, [], {
            detached: true,
            stdio: "ignore",
        });
        child.once("error", () => reject(new Error("Could not open T3 Code Nightly.")));
        child.once("spawn", () => {
            child.unref();
            resolve();
        });
    });
}

function delay(milliseconds) {
    return new Promise(resolve => setTimeout(resolve, milliseconds));
}

async function waitForT3CodeRelayCredentials(interactive) {
    const current = await t3CodeRelayCredentials();
    if (current)
        return current;
    if (!interactive)
        throw new Error("Sign in to T3 Connect in T3 Code Nightly, then try again.");

    await openT3Code();
    const deadline = Date.now() + LOGIN_TIMEOUT_MS;
    while (Date.now() < deadline) {
        await delay(SIGN_IN_POLL_MS);
        const credentials = await t3CodeRelayCredentials();
        if (credentials)
            return credentials;
    }
    throw new Error("T3 Connect sign-in timed out. Sign in in T3 Code Nightly, then try again.");
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
    if (credentials?.source !== "t3code-session" || !credentials.accessToken)
        throw new Error("A T3 Code Nightly sign-in is required for T3 Connect.");
    const currentCredentials = credentials;
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
    const credentials = await waitForT3CodeRelayCredentials(false);
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
        const credentials = await waitForT3CodeRelayCredentials(false);
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
    const connection = await readJson(STATE_PATHS.connection);
    let credentials = null;
    try {
        credentials = await t3CodeRelayCredentials();
    } catch {
        // Status is informational; the next explicit sign-in surfaces details.
    }
    return {
        signedIn: Boolean(credentials?.accessToken),
        identity: credentials?.identity || connection?.cloudIdentity || "",
        status: connection?.cloudStatus || (credentials ? "signed-in" : "signed-out"),
        environmentId: connection?.environmentId || "",
        environmentLabel: connection?.environmentLabel || "",
    };
}

async function removeCloudState() {
    await Promise.all([
        fs.rm(STATE_PATHS.legacyCredentials, { force: true }),
        fs.rm(STATE_PATHS.dpopKey, { force: true }),
        fs.rm(STATE_PATHS.connection, { force: true }),
    ]);
}

async function loginAndConnect() {
    try {
        const credentials = await waitForT3CodeRelayCredentials(true);
        const result = await connectCloud(credentials);
        return {
            status: result.cloudStatus,
            identity: result.cloudIdentity,
            environmentId: result.environmentId || "",
            environmentLabel: result.environmentLabel || "",
        };
    } finally {
        // Nightly and its browser sign-in steal focus. Return to the module on
        // success and failures so the result never disappears behind them.
        activatePanel();
    }
}

async function main(argv) {
    const command = argv[2] || "status";
    let result;
    if (command === "login")
        result = await loginAndConnect();
    else if (command === "connect") {
        const connected = await connectCloud(await waitForT3CodeRelayCredentials(false));
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
