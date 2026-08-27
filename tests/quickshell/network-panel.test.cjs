const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

function read(relative) {
    return fs.readFileSync(path.join(shellDir, relative), "utf8");
}

test("the wide Network panel has a physical-transport hero and live diagnostic grid", () => {
    const panel = read("Popovers/WifiPopover.qml");
    assert.match(panel, /implicitWidth:\s*Math\.min\(600/);
    assert.match(panel, /readonly property var primary:\s*NetworkDetails\.primary/);
    for (const label of ["Ping", "Packet loss", "Receive", "Send", "Downloaded",
        "Uploaded", "IPv4 address", "Gateway"])
        assert.match(panel, new RegExp(`label: "${label}"`));
    assert.match(panel, /NetworkHelpers\.formatRate\(NetworkDetails\.downloadRate\)/);
    assert.match(panel, /NetworkHelpers\.formatBytes\(root\.primary\.rxBytes\)/);
});

test("network details poll only while acquired and serialize snapshots", () => {
    const controller = read("Common/NetworkDetails.qml");
    assert.match(controller, /function acquire\(\)/);
    assert.match(controller, /function release\(\)/);
    assert.match(controller, /readonly property int pollIntervalMs:\s*1500/);
    assert.match(controller, /interval:\s*root\.pollIntervalMs/);
    assert.match(controller, /pollCadenceText:/,
        "the visible cadence label must come from the actual polling interval");
    assert.match(controller, /running:\s*root\.acquired/);
    assert.match(controller, /if \(snapshotProc\.running\)[\s\S]*snapshotAgain = true/);
    assert.match(controller, /scannerDevice\.scannerEnabled = false/);
    assert.match(controller, /NetworkHelpers\.calculateRates/);
    assert.match(controller, /NetworkHelpers\.updatePingHistory/);
});

test("DNS controls remain profile-backed and Wi-Fi band options stay out of the view", () => {
    const panel = read("Popovers/WifiPopover.qml");
    const controller = read("Common/NetworkDetails.qml");
    assert.match(panel, /model:\s*\["Automatic", "Cloudflare", "Google", "Custom"\]/);
    assert.match(panel, /NetworkHelpers\.validateDnsServers/);
    assert.match(panel, /NetworkDetails\.dnsMixed/);
    assert.match(panel, /NetworkDetails\.dnsNotice/);
    assert.doesNotMatch(panel, /WI-FI BAND/);
    assert.doesNotMatch(panel, /NetworkDetails\.bandAvailable/);
    assert.doesNotMatch(panel, /NetworkDetails\.setBand/);
    assert.match(controller, /command:\s*\["python3", root\.helper, "dns"\]/);
});

test("Wi-Fi defaults to a connected-network picker and expands all actionable rows", () => {
    const panel = read("Popovers/WifiPopover.qml");
    assert.match(panel, /property bool wifiNetworksOpen:\s*false/);
    assert.match(panel, /component WifiNetworkPicker:\s*Rectangle/);
    assert.match(panel, /id:\s*wifiPicker[\s\S]{0,300}currentLabel:\s*root\.connectedWifiName/);
    assert.match(panel, /expanded:\s*root\.wifiNetworksOpen/);
    assert.match(panel, /id:\s*wifiNetworkList[\s\S]{0,80}visible:\s*root\.wifiNetworksOpen/);
    assert.match(panel, /function collapseWifiNetworks\(\)[\s\S]{0,100}clearCredentials\(\)/);
    assert.match(panel, /text:\s*"KNOWN NETWORKS"/);
    assert.match(panel, /text:\s*"OTHER NETWORKS"/);
    assert.match(panel, /model:\s*root\.wifiNetworksOpen && WifiState\.enabled\s*\? NetworkDetails\.knownNetworks/);
    assert.match(panel, /model:\s*root\.wifiNetworksOpen && WifiState\.enabled\s*\? NetworkDetails\.otherNetworks/);
    assert.match(panel, /action:\s*"disconnect"/);
    assert.match(panel, /action:\s*"forget"/);
    assert.match(panel, /credentialIdentity/);
    assert.match(panel, /echoMode:\s*TextInput\.Password/);
    assert.match(panel, /Certificates\? Network Settings/);
    assert.match(panel, /function clearCredentials\(\)/);
    assert.match(panel, /if \(runConnectRequest\(request\)\)\s*clearCredentials\(\)/);
    assert.match(panel, /NetworkDetails\.wifiError\(network\.ssid\)/);
});

test("every managed Ethernet port retains loading, absent, failure and compact states", () => {
    const panel = read("Popovers/WifiPopover.qml");
    assert.match(panel, /text:\s*"ETHERNET"/);
    assert.match(panel, /model:\s*EthernetState\.devices/);
    assert.match(panel, /Checking Ethernet…/);
    assert.match(panel, /Ethernet status unavailable/);
    assert.match(panel, /No Ethernet ports/);
    assert.match(panel, /ethernetRow\.modelData\.device \+ " · "/);
});

test("one disposable network overlay is registered at shell scope", () => {
    const shell = read("shell.qml");
    const overlay = read("NetworkOverlayWindow.qml");
    const state = read("Common/NetworkOverlayState.qml");
    assert.equal((shell.match(/NetworkOverlayWindow\s*\{/g) || []).length, 1);
    assert.match(state, /function openQr\(screen, interfaceName\)/);
    assert.match(state, /function openSpeedTest\(screen, interfaceName\)/);
    assert.match(state, /property var speedDevices:\s*\[\]/);
    assert.match(state, /NetworkDetails\.physicalDevices\.filter/);
    assert.match(state, /function selectSpeedInterface\(interfaceName\)/);
    assert.match(state, /function close\(\)/);
    assert.match(state, /Popouts\.close\(\)/);
    assert.match(state, /Launcher\.close\(\)/);
    assert.match(overlay, /active:\s*NetworkOverlayState\.open/);
    assert.match(overlay, /sourceComponent:\s*NetworkOverlayState\.page === "qr" \? qrPage : speedPage/);
    assert.match(overlay, /Keys\.onEscapePressed:\s*NetworkOverlayState\.close\(\)/);
    assert.match(overlay, /onClicked:\s*NetworkOverlayState\.close\(\)/);
});

test("QR generation is immediate and sustained speed tests support device switching", () => {
    const overlay = read("NetworkOverlayWindow.qml");
    assert.match(overlay, /stdinEnabled:\s*true/);
    assert.match(overlay, /Component\.onCompleted:[\s\S]{0,400}startQr\(\)/);
    assert.match(overlay, /pendingQrRequest = \{[\s\S]{0,100}uuid: info\.uuid/);
    assert.doesNotMatch(overlay, /Reveal password & QR/);
    assert.doesNotMatch(overlay, /id:\s*passwordProc/);
    assert.match(overlay, /Component\.onDestruction:[\s\S]{0,200}matrix = \[\]/);
    assert.match(overlay, /text:\s*"TEST DEVICE"/);
    assert.match(overlay, /function chooseInterface\(interfaceName\)/);
    assert.match(overlay, /NetworkOverlayState\.selectSpeedInterface\(selectedInterface\)/);
    assert.match(overlay, /command:\s*\["python3", root\.speedHelper, "--interface"/);
    assert.match(overlay, /speedProc\.signal\(15\)/);
    assert.match(overlay,
        /label:\s*speedProc\.running\s*\?\s*"Cancel"\s*:\s*"Run Again"/);
    assert.match(overlay, /component SpeedDial:/);

    const speedHelper = read("scripts/network-speedtest.py");
    assert.match(speedHelper, /api\.fast\.com\/netflix\/speedtest\/v2/);
    assert.match(speedHelper, /NETWORK_SPEEDTEST_PARALLEL", 8/);
    assert.match(speedHelper, /NETWORK_SPEEDTEST_PHASE_SECONDS", 5\.0/);
    assert.match(speedHelper, /rx_bytes/);
    assert.match(speedHelper, /tx_bytes/);
    assert.match(speedHelper, /"--interface", interface/);
});

test("new runtime commands are explicit desktop dependencies", () => {
    const tasks = fs.readFileSync(path.resolve(shellDir, "../../tasks/main.yml"), "utf8");
    for (const dependency of ["NetworkManager", "python3", "curl", "iw", "qrencode", "iproute", "iputils", "dnf5-plugins"])
        assert.match(tasks, new RegExp(`- ${dependency}(?:\\s|$)`));
});
