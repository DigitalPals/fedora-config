const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./shell.cjs");

const H = load("NetworkHelpers.js");

test("the cheapest physical default route wins over VPN and Tailscale routes", () => {
    const devices = [
        { interface: "tailscale0", type: "tun", connected: true },
        { interface: "wg0", type: "wireguard", connected: true },
        { interface: "wlan0", type: "wifi", connected: true },
        { interface: "eth0", type: "ethernet", connected: true }
    ];
    const routes = [
        { dev: "tailscale0", metric: 1 },
        { dev: "wg0", metric: 5 },
        { dev: "wlan0", metric: 600 },
        { dev: "eth0", metric: 100 }
    ];
    assert.equal(H.selectPrimaryInterface(devices, routes).interface, "eth0");
    assert.equal(H.selectPrimaryInterface(devices, routes.filter(route => route.dev !== "eth0")).interface,
        "wlan0");
});

test("primary-interface fallback is deterministic Ethernet then Wi-Fi", () => {
    const devices = [
        { interface: "wlan1", type: "wifi", connected: true },
        { interface: "enp2s0", type: "ethernet", connected: true },
        { interface: "enp1s0", type: "ethernet", connected: true }
    ];
    assert.equal(H.selectPrimaryInterface(devices, []).interface, "enp1s0");
    assert.equal(H.selectPrimaryInterface(devices.filter(device => device.type === "wifi"), []).interface,
        "wlan1");
    assert.equal(H.selectPrimaryInterface([{ interface: "tun0", type: "tun", connected: true }], []),
        null);
});

test("rate deltas reset on first sample, interface change, and counter rollback", () => {
    const first = H.calculateRates(null, { interface: "eth0", rxBytes: 1000, txBytes: 500 }, 1000);
    assert.equal(first.reset, true);
    assert.equal(first.download, 0);
    const second = H.calculateRates(first.next,
        { interface: "eth0", rxBytes: 3000, txBytes: 1500 }, 3000);
    assert.equal(second.reset, false);
    assert.equal(second.download, 1000);
    assert.equal(second.upload, 500);
    assert.equal(H.calculateRates(second.next,
        { interface: "wlan0", rxBytes: 9000, txBytes: 9000 }, 4000).reset, true);
    assert.equal(H.calculateRates(second.next,
        { interface: "eth0", rxBytes: 1, txBytes: 1 }, 4000).reset, true);
});

test("ping windows retain losses and average recent successful probes", () => {
    let history = [];
    for (const sample of [10, null, 20, null, 30])
        history = H.updatePingHistory(history, sample, 4);
    assert.deepEqual(history, [null, 20, null, 30]);
    assert.deepEqual(H.pingStats(history, 2), { latency: 25, loss: 50, samples: 4 });
});

test("network quantities format compactly", () => {
    assert.equal(H.formatBytes(0), "0 B");
    assert.equal(H.formatBytes(1536), "1.5 KB");
    assert.equal(H.formatRate(1024 * 1024), "1 MB/s");
    assert.equal(H.formatLatency(4.25), "4.3 ms");
    assert.equal(H.formatLatency(null), "--");
});

test("Wi-Fi scans deduplicate SSIDs, retain bands, and split known networks", () => {
    const grouped = H.groupWifiNetworks([
        { ssid: "Cafe", bssid: "a", signal: 22, frequency: 2412, security: "WPA2" },
        { ssid: "Cafe", bssid: "b", signal: 91, frequency: 5975, security: "WPA3" },
        { ssid: "Guest", signal: 70, frequency: 5180, security: "OWE" }
    ], [{ ssid: "Cafe", name: "Cafe profile", uuid: "u", type: "wifi" }]);
    assert.equal(grouped.known.length, 1);
    assert.equal(grouped.known[0].ssid, "Cafe");
    assert.equal(grouped.known[0].signal, 91);
    assert.deepEqual(grouped.known[0].bands, ["2.4", "6"]);
    assert.equal(grouped.known[0].profileUuid, "u");
    assert.deepEqual(grouped.other.map(network => network.ssid), ["Guest"]);
});

test("security classification covers open, OWE, personal, WEP, PEAP, and certificates", () => {
    assert.equal(H.classifySecurity("--").kind, "open");
    assert.equal(H.classifySecurity("OWE").kind, "owe");
    assert.equal(H.classifySecurity("WPA2 WPA3").kind, "wpa3");
    assert.equal(H.classifySecurity("WEP").kind, "wep");
    assert.deepEqual(H.classifySecurity("WPA2-EAP PEAP MSCHAPV2"), {
        kind: "enterprise-peap", label: "Enterprise", password: true,
        identity: true, supported: true, shareable: false, qrType: ""
    });
    assert.equal(H.classifySecurity("WPA2-EAP TLS").supported, false);
});

test("custom DNS validation accepts literal IPs, deduplicates, and caps at four", () => {
    assert.deepEqual(H.validateDnsServers("1.1.1.1, 1.1.1.1 2606:4700:4700::1111"), {
        valid: true, servers: ["1.1.1.1", "2606:4700:4700::1111"], error: ""
    });
    assert.equal(H.validateDnsServers("resolver.example").valid, false);
    assert.equal(H.validateDnsServers("01.1.1.1").valid, false);
    assert.equal(H.validateDnsServers("1.1.1.1 2.2.2.2 3.3.3.3 4.4.4.4 5.5.5.5").valid,
        false);
});

test("DNS state ignores non-physical and attached profiles and reports Mixed", () => {
    const automatic = {
        type: "ethernet", ipv4Dns: [], ipv6Dns: [],
        ipv4IgnoreAutoDns: false, ipv6IgnoreAutoDns: false
    };
    const google = {
        type: "wifi", ipv4Dns: ["8.8.8.8", "8.8.4.4"],
        ipv6Dns: ["2001:4860:4860::8888", "2001:4860:4860::8844"],
        ipv4IgnoreAutoDns: true, ipv6IgnoreAutoDns: true
    };
    assert.equal(H.dnsState([automatic, google]).provider, "Mixed");
    assert.equal(H.dnsState([google, { type: "tun", ipv4Dns: ["9.9.9.9"] }]).provider,
        "Google");
    assert.equal(H.dnsState([{ ...google, controller: "bridge0" }]).provider, "Automatic");
});

test("band availability is derived only from the active SSID", () => {
    const scans = [
        { ssid: "Home", frequency: 2412 },
        { ssid: "Home", frequency: 5500 },
        { ssid: "Home", frequency: 6375 },
        { ssid: "Other", frequency: 2412 }
    ];
    assert.deepEqual(H.availableBands(scans, "Home"), ["2.4", "5", "6"]);
    assert.deepEqual(H.bandState({ selectedBand: "auto" }, scans, "Home", 6375), {
        selected: "auto", current: "6", available: ["2.4", "5", "6"], automatic: true
    });
});
