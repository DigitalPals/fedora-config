const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

function read(relative) {
    return fs.readFileSync(path.join(shellDir, relative), "utf8");
}

function objectBlock(source, start) {
    let depth = 0;
    const opening = source.indexOf("{", start);
    for (let index = opening; index < source.length; index++) {
        if (source[index] === "{")
            depth++;
        else if (source[index] === "}" && --depth === 0)
            return source.slice(start, index + 1);
    }
    assert.fail("unterminated QML object block");
}

test("the Internet row always opens Network details and never toggles Wi-Fi", () => {
    const source = read("Popovers/ControlCenterPopover.qml");
    const title = source.indexOf('title: "Internet"');
    assert.ok(title >= 0);
    const start = source.lastIndexOf("RadioRow {", title);
    const row = objectBlock(source, start);

    assert.match(row, /onActivated:\s*Popouts\.openPanel\("wifi", "right"\)/);
    assert.doesNotMatch(row, /WifiState\.setEnabled/);
    for (const label of ["Ethernet + Wi-Fi", "Ethernet", "No connection", "Offline"])
        assert.match(row, new RegExp(label.replace(/[+]/g, "\\+")));
    assert.match(row, /on:\s*EthernetState\.connected \|\| WifiState\.connected/);

    // One activation, not three. Left-click, right-click and the chevron's own
    // hit area all used to call openPanel() with the same arguments — three
    // targets for one outcome, and a chevron that looked like it did something
    // the row did not.
    const radioRow = objectBlock(source, source.indexOf("component RadioRow:"));
    assert.match(radioRow, /onClicked:\s*radio\.activated\(\)/);
    assert.doesNotMatch(radioRow, /RightButton/,
        "a radio row has one outcome, so it must not split the mouse buttons");
    assert.equal(radioRow.match(/MouseArea\s*\{/g).length, 1,
        "the whole row is the hit target — no separate chevron MouseArea");
});

test("the Bluetooth row always opens details and never toggles the radio", () => {
    const source = read("Popovers/ControlCenterPopover.qml");
    const title = source.indexOf('title: "Bluetooth"');
    assert.ok(title >= 0);
    const start = source.lastIndexOf("RadioRow {", title);
    const row = objectBlock(source, start);

    assert.match(row,
        /onActivated:\s*Popouts\.openPanel\("bluetooth", "right"\)/);
    assert.doesNotMatch(row, /BluetoothState\.toggle/);
});

test("the stable wifi popout is a scrollable Ethernet and Wi-Fi Network view", () => {
    const source = read("Popovers/WifiPopover.qml");
    assert.match(source, /text:\s*"Network"/);
    assert.match(source, /text:\s*"ETHERNET"/);
    assert.match(source, /model:\s*EthernetState\.devices/);
    assert.match(source, /model:\s*WifiState\.others/);
    assert.match(source, /Flickable\s*\{/);
    assert.match(source, /ScrollChrome\s*\{/);
    assert.match(source, /checked:\s*WifiState\.enabled/);
    assert.match(source, /onToggled:\s*value => root\.setWifiEnabled\(value\)/);
    assert.match(source,
        /function setWifiEnabled\(value\)[\s\S]{0,100}WifiState\.setEnabled\(value\)/);
    assert.match(source, /text:\s*"Network settings"/);
    assert.match(source, /gnome-control-center network/);
    assert.doesNotMatch(source, /gnome-control-center wifi/);
});

test("Ethernet loading, absence and read failures are separate UI states", () => {
    const source = read("Popovers/WifiPopover.qml");
    assert.match(source, /!EthernetState\.known/);
    assert.match(source, /Checking Ethernet…/);
    assert.match(source, /EthernetState\.error !== ""/);
    assert.match(source, /Ethernet status unavailable/);
    assert.match(source, /EthernetState\.devices\.length === 0/);
    assert.match(source, /No Ethernet ports/);
});

test("the combined menubar indicator gives wired transport priority", () => {
    const module = read("Bar/Modules/Wifi.qml");
    assert.match(module, /moduleId:\s*"wifi"/);
    assert.match(module, /panelName:\s*"wifi"/);
    assert.match(module, /EthernetState\.connected \? "lan"/);
    assert.match(module, /EthernetState\.connected \|\| WifiState\.connected/);
    assert.match(module, /for \(const device of EthernetState\.connectedDevices\)/);
    assert.match(module, /"Ethernet " \+ \(device\.connection \|\| device\.device\)/);
    assert.match(module, /"Wi-Fi " \+ WifiState\.name/);
});

test("wired monitoring is ref-counted by each visible Network consumer", () => {
    const singleton = read("Common/EthernetState.qml");
    const module = read("Bar/Modules/Wifi.qml");
    const popover = read("Popovers/WifiPopover.qml");
    const control = read("Popovers/ControlCenterPopover.qml");

    assert.match(singleton, /function acquire\(\)/);
    assert.match(singleton, /function release\(\)/);
    assert.match(singleton, /"nmcli", "device", "monitor"/);
    assert.match(singleton, /property bool known:/);
    assert.match(singleton, /property string error:/);
    assert.match(singleton, /readonly property var connectedDevices:/);
    for (const source of [module, popover, control]) {
        assert.match(source, /EthernetState\.acquire\(\)/);
        assert.match(source, /EthernetState\.release\(\)/);
    }
});

test("the visible widget label is Network while stable identifiers stay wifi", () => {
    const registry = read("Common/PanelRegistryData.js");
    const catalog = require(path.join(shellDir, "Common", "WidgetCatalog.js"));
    assert.equal(catalog.widgetName("wifi"), "Network");
    assert.match(registry, /name: "wifi"[\s\S]*source: "Popovers\/WifiPopover\.qml"/);
});
