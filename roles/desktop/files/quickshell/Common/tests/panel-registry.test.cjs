const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const R = require("../PanelRegistryData.js");
const SettingsHelpers = require("../SettingsHelpers.js");

const shellDir = path.resolve(__dirname, "../..");

function read(relative) {
    return fs.readFileSync(path.join(shellDir, relative), "utf8");
}


// The bar and the module files it loads, as one corpus: ownership is declared
// in Bar/Modules/*.qml now, while the slot that drives it is in Bar.qml.
function barSources() {
    const dir = path.join(shellDir, "Bar", "Modules");
    return [read("Bar/Bar.qml"),
            ...fs.readdirSync(dir).filter(f => f.endsWith(".qml"))
                .map(f => fs.readFileSync(path.join(dir, f), "utf8"))].join("\n");
}

// The whole point of the registry: these assertions are what used to be a
// human remembering four separate maps. Each one fails on a panel added to
// one place but not another.

test("every panel's view exists on disk", () => {
    for (const panel of R.PANELS) {
        assert.ok(fs.existsSync(path.join(shellDir, panel.source)),
            `${panel.name} points at a missing file: ${panel.source}`);
    }
});

test("panel names and module ids are unique", () => {
    const names = R.names();
    assert.equal(new Set(names).size, names.length, "duplicate panel name");
    const owned = R.PANELS.map(p => p.moduleId).filter(id => id !== "");
    assert.equal(new Set(owned).size, owned.length, "two panels claim one module");
});

test("every island is a real bar section", () => {
    for (const panel of R.PANELS)
        assert.ok(["left", "center", "right"].includes(panel.island),
            `${panel.name} has island "${panel.island}"`);
});

test("the module id space and the panel space account for each other", () => {
    // Catches a typo'd moduleId in either direction, which would otherwise
    // surface as a popout that silently never opens.
    const ids = SettingsHelpers.defaults().mods;
    const known = new Set();
    for (const col of ["left", "center", "right"])
        for (const mod of ids[col])
            known.add(mod.id);

    for (const panel of R.PANELS) {
        if (panel.moduleId !== "")
            assert.ok(known.has(panel.moduleId),
                `${panel.name} claims module "${panel.moduleId}", which is not a bar module`);
    }

    const claimed = new Set(R.PANELS.map(p => p.moduleId).filter(id => id !== ""));
    for (const id of known) {
        if (!R.PANEL_LESS_MODULES.includes(id))
            assert.ok(claimed.has(id),
                `module "${id}" opens no panel — add one, or list it in PANEL_LESS_MODULES`);
    }
    for (const id of R.PANEL_LESS_MODULES)
        assert.ok(known.has(id), `PANEL_LESS_MODULES names "${id}", which is not a bar module`);
});

test("every panel the bar claims is a registry panel", () => {
    // Modules declare ownership as `panelName: "x"` on a BarIcon/BarChip/
    // T3Chip/UsageChips; the primitive turns that into the registerPanel
    // call, the held state and the hover/click wiring.
    const bar = barSources();
    const registered = [...bar.matchAll(/panelName:\s*"([a-z0-9]+)"/g)].map(m => m[1]);
    assert.ok(registered.length > 0, "no panelName declarations found — did Bar/Modules/ move?");
    const names = new Set(R.names());
    for (const name of registered)
        assert.ok(names.has(name), `Bar.qml registers "${name}", which is not in the registry`);
});

test("a bar module that owns a panel registers it under the registry's name", () => {
    // The pairing that actually breaks: cmpClock opens "calendar", not
    // "clock". A moduleId pointing at the wrong panel is invisible otherwise.
    const bar = barSources();
    const registered = new Set(
        [...bar.matchAll(/panelName:\s*"([a-z0-9]+)"/g)].map(m => m[1]));
    for (const panel of R.PANELS) {
        if (panel.moduleId === "")
            continue;
        assert.ok(registered.has(panel.name),
            `${panel.name} is owned by module "${panel.moduleId}" but no bar module claims it`);
    }
});

test("panels no module owns are exactly the ones the bar sweep must skip", () => {
    // The Tailscale bug in one assertion: an ownerless panel left in the
    // sweep gets closed by any unrelated module change.
    assert.deepEqual(R.PANELS.filter(p => R.ownerless(p.name)).map(p => p.name).sort(),
        ["settings", "tailscale"]);
});

test("only settings carries the behaviour flags", () => {
    // Each flag replaced a hardcoded `=== "settings"`. If a second panel ever
    // needs one, the consumers already handle it — but say so deliberately.
    for (const flag of ["centerAnchored", "fillsBody", "persistsAcrossHosts"]) {
        const carrying = R.PANELS.filter(p => p[flag]).map(p => p.name);
        assert.deepEqual(carrying, [R.SETTINGS], `unexpected panels carry ${flag}`);
    }
});

test("no consumer still hardcodes a panel name it should ask the registry for", () => {
    // Guards the substitution this WP made: these files used to test
    // `Popouts.currentName === "settings"` directly.
    for (const file of ["shell.qml", "Bar/Bar.qml", "Bar/IslandPopout.qml",
                        "Bar/BarPopoutWindow.qml"]) {
        // Line by line, so a failure names the offending line rather than
        // dumping the whole file into the assertion diff.
        read(file).split("\n").forEach((line, i) => {
            assert.ok(!/currentName\s*[!=]==\s*"settings"/.test(line),
                `${file}:${i + 1} compares currentName against a literal panel name:\n    ${line.trim()}`);
        });
    }
});

test("lookups answer for unknown panels instead of throwing", () => {
    // Popouts.openPanel() and the IPC handler both accept arbitrary strings.
    assert.equal(R.byName("nope"), null);
    assert.equal(R.island("nope"), "right");
    assert.equal(R.moduleFor("nope"), "");
    assert.equal(R.panelForModule("nope"), "");
    assert.equal(R.panelForModule(""), "");
    assert.equal(R.centerAnchored("nope"), false);
    assert.equal(R.fillsBody("nope"), false);
    assert.equal(R.persistsAcrossHosts("nope"), false);
    assert.equal(R.ownerless("nope"), true);
});

test("the derived maps cover every panel", () => {
    const islands = R.islandMap();
    const sources = R.sourceMap("prefix/");
    for (const panel of R.PANELS) {
        assert.equal(islands[panel.name], panel.island);
        assert.equal(sources[panel.name], "prefix/" + panel.source);
    }
    assert.equal(Object.keys(islands).length, R.PANELS.length);
    assert.equal(Object.keys(sources).length, R.PANELS.length);
    assert.equal(R.sourceMap().control, "Popovers/ControlCenterPopover.qml");
});

test("panelName is what actually drives the panel wiring", () => {
    // Otherwise the assertions above would pass against a dead property.
    for (const file of ["Bar/BarIcon.qml", "Bar/BarChip.qml", "Bar/T3Chip.qml",
                        "Bar/UsageChips.qml"]) {
        const src = read(file);
        assert.match(src, /property string panelName/, `${file} must accept panelName`);
        assert.match(src, /host\.registerPanel\(panelName/, `${file} must register it`);
        assert.match(src, /host\.unregisterPanel\(panelName/, `${file} must unregister it`);
        assert.match(src, /host\.popoutOpen\(panelName\)/, `${file} must derive held from it`);
        // Typed, so a misspelt call is a lint error rather than a silent no-op.
        assert.match(src, /property Bar host/, `${file} must type its host as Bar`);
    }
});

test("no bar module hand-wires a panel the primitive already owns", () => {
    // One exception, commented as such: the usage module's per-provider clicks
    // select a provider or close, which the generic toggle cannot express.
    const bar = barSources();
    for (const call of ["registerPanel", "unregisterPanel", "togglePopout"]) {
        assert.doesNotMatch(bar, new RegExp(`barWindow\\.${call}\\(`),
            `Bar.qml still hand-wires ${call}; panelName should drive it`);
    }
    // Modules reach the bar as `host` now, so count there rather than on the
    // old outer id. Two sites, both in Usage: its chips are per-provider
    // hover targets under one popout anchor.
    const dir = path.join(shellDir, "Bar", "Modules");
    const hoverSites = fs.readdirSync(dir).filter(f => f.endsWith(".qml"))
        .flatMap(f => [...fs.readFileSync(path.join(dir, f), "utf8")
            .matchAll(/host\.(hoverOpen|cancelHover)\(/g)].map(() => f));
    assert.deepEqual(hoverSites, ["Usage.qml", "Usage.qml"],
        "only the usage module's bespoke per-provider hover should remain");
});
