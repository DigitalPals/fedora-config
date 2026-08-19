const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir, load } = require("./shell.cjs");

const R = load("PanelRegistryData.js");
const SettingsHelpers = load("SettingsHelpers.js");

function read(relative) {
    return fs.readFileSync(path.join(shellDir, relative), "utf8");
}

// The bar and the module files it loads, as one corpus: ownership is declared
// in Bar/Modules/*.qml now, while the slot that drives it is in Bar.qml.
function barSources() {
    const dir = path.join(shellDir, "Bar", "Modules");
    return [read("Bar/Bar.qml"), read("Bar/Cluster.qml"),
            ...fs.readdirSync(dir).filter(f => f.endsWith(".qml"))
                .map(f => fs.readFileSync(path.join(dir, f), "utf8"))].join("\n");
}

// Every panel name the bar claims: a module's own `panelName: "x"`, plus the
// two the cluster's group pills open, which come from a named map rather than
// from a module because the pill is furniture the modules sit inside.
function claimedPanels() {
    const bar = barSources();
    const groupMap = read("Bar/Cluster.qml")
        .match(/groupPanels:\s*\(\{([\s\S]*?)\}\)/)?.[1] ?? "";
    assert.ok(groupMap.trim() !== "", "Cluster.qml no longer maps groups to panels");
    return new Set([
        ...[...bar.matchAll(/panelName:\s*"([a-z0-9]+)"/g)].map(m => m[1]),
        ...[...groupMap.matchAll(/"([a-z0-9]+)"/g)].map(m => m[1])
    ]);
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
    const registered = [...claimedPanels()];
    assert.ok(registered.length > 0, "no panelName declarations found — did Bar/Modules/ move?");
    const names = new Set(R.names());
    for (const name of registered)
        assert.ok(names.has(name), `the bar registers "${name}", which is not in the registry`);
});

test("a bar module that owns a panel registers it under the registry's name", () => {
    // The pairing that actually breaks: cmpClock opens "calendar", not
    // "clock". A moduleId pointing at the wrong panel is invisible otherwise.
    const registered = claimedPanels();
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
    // The redesign added to this set on purpose. `control` is opened by the
    // status pill, which is furniture the status modules fill in rather than a
    // module of its own; the four detail panels behind it and the two the
    // notification centre absorbed are now reachable only from IPC or from
    // inside another panel. None of them can be closed by a module going away,
    // so none of them may be swept.
    assert.deepEqual(R.PANELS.filter(p => R.ownerless(p.name)).map(p => p.name).sort(),
        ["audio", "battery", "bluetooth", "calendar", "control", "settings",
         "tailscale", "weather", "wifi"]);
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
    for (const file of ["shell.qml", "Bar/Bar.qml", "Bar/PopoutHost.qml",
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
    // The IPC boundary accepts arbitrary strings; registry lookups themselves
    // remain total so every caller can decide how to handle one.
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

test("the IPC boundary rejects unknown names before mapping a ghost surface", () => {
    const popouts = read("Common/Popouts.qml");
    const openPanel = popouts.match(/function openPanel\([\s\S]*?\n    \}/)?.[0] ?? "";

    assert.match(openPanel, /PanelRegistry\.byName\(name\) === null/);
    assert.ok(openPanel.indexOf("PanelRegistry.byName(name)") < openPanel.indexOf("open = true"),
        "validation must happen before the layer surface is asked to map");
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
    for (const file of ["Bar/BarIcon.qml", "Bar/BarChip.qml",
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

test("a primitive that registers a panel also opens it", () => {
    // The half that registration does not cover: a chip whose own click is
    // unwired looks dead. T3Chip shipped that way once — it registered,
    // derived held, and did nothing when clicked.
    //
    // UsageChips is the exception, and the test below pins it as the only
    // one: its per-provider clicks select a provider or close, which the
    // generic toggle cannot express, so Usage.qml wires those at the module.
    for (const file of ["Bar/BarIcon.qml", "Bar/BarChip.qml"]) {
        const src = read(file);
        assert.match(src, /host\.togglePopout\(\s*(root\.)?panelName/,
            `${file} registers a panel but never toggles it on click`);
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
});

test("menu hover switching is latched behind an open popout", () => {
    const host = read("Bar/Bar.qml");
    const icon = read("Bar/BarIcon.qml");
    const chip = read("Bar/BarChip.qml");
    const cluster = read("Bar/Cluster.qml");

    // Merely crossing the bar must remain inert. Once a click has opened any
    // popout, entering another owner morphs the existing surface immediately.
    assert.match(host,
        /function hoverPopout\([^)]*\) \{\s*if \(!Popouts\.open\)\s*return false;/,
        "closed-bar hover must not start a menu session");
    assert.match(host,
        /if \(Popouts\.currentName !== name\)\s*Popouts\.openPanel\(name, isle, anchorOf\(item\)\)/,
        "an open menu session must switch to the hovered panel");

    for (const [file, src] of [["BarIcon.qml", icon], ["BarChip.qml", chip]]) {
        assert.match(src, /onEntered:[\s\S]{0,180}?host\.hoverPopout\(root\.panelName/,
            `${file} does not switch the latched menu on enter`);
        assert.match(src, /onPositionChanged:[\s\S]{0,180}?host\.hoverPopout\(root\.panelName/,
            `${file} cannot recover an enter lost while mapping a layer surface`);
    }
    assert.match(cluster,
        /onEntered:\s*root\.host\.hoverPopout\(group\.panelName, root\.col, pill\)/,
        "group-owned status and centre menus must join hover switching");
    assert.match(cluster,
        /onPositionChanged:\s*root\.host\.hoverPopout\(group\.panelName, root\.col, pill\)/);

    // A newly mapped layer surface can cost every child target its next event;
    // the full-bar handler must independently hit-test the panel registry.
    assert.match(host,
        /function hoverPanelAt\(position\)[\s\S]*Object\.keys\(panelAnchors\)/,
        "the bar-wide fallback must inspect every registered panel anchor");
    assert.match(host,
        /onPointChanged:[\s\S]{0,260}?barWindow\.hoverPanelAt\(scenePoint\)/,
        "full-bar pointer motion must drive the fallback hit test");
});

// Text at the immediate level of a QML block, with nested objects removed, so
// a property set on a child is not mistaken for one set here.
function topLevel(body) {
    let previous;
    do {
        previous = body;
        body = body.replace(/\{[^{}]*\}/g, " ");
    } while (body !== previous);
    return body;
}

function barQmlFiles() {
    const found = [];
    const walk = dir => {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory())
                walk(full);
            else if (entry.name.endsWith(".qml"))
                found.push(full);
        }
    };
    walk(path.join(shellDir, "Bar"));
    return found;
}

// What each bar primitive cannot be built without. A MouseArea on a layer
// surface can miss its exit event, so nothing that draws a hover state may
// rely on `containsMouse` alone: PointerCheck is the second opinion, and these
// are the wires that reach it. The idle module was instantiated without a
// `host` — it owns no panel, so nothing else in the chip needed the bar — and
// its tooltip then stayed on screen long after the pointer had left, with no
// path back to false.
//
// qmllint fails these too, now that they are `required` and RequiredProperty
// is an error. Kept here as well because this states *why*, and because the
// lint sweep SKIPs when qmllint is not installed.
const REQUIRED_WIRING = {
    BarIcon: ["host"],
    BarChip: ["host"],
    BarTooltip: ["check"],
    PointerCheck: ["host", "target", "hovered"],
};

test("every bar primitive that draws a hover state is fully wired", () => {
    const offenders = [];
    for (const file of barQmlFiles()) {
        const src = fs.readFileSync(file, "utf8")
            // Strings before comments: a stripped string cannot then look
            // like the start of one.
            .replace(/"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'/g, '""')
            .replace(/\/\/[^\n]*/g, "");
        const types = Object.keys(REQUIRED_WIRING).join("|");
        // The first type declaration in a file is its root: a file rooted at
        // BarChip is a new kind of chip, and its `host` is set where it is
        // used, not where it is defined.
        const rootStart = src.search(/^[A-Z]\w*\s*\{/m);
        for (const match of src.matchAll(new RegExp(`\\b(${types})\\s*\\{`, "g"))) {
            if (match.index === rootStart)
                continue;
            const start = match.index + match[0].length - 1;
            let depth = 0;
            let end = start;
            while (end < src.length) {
                if (src[end] === "{")
                    depth++;
                else if (src[end] === "}" && --depth === 0)
                    break;
                end++;
            }
            const body = topLevel(src.slice(start + 1, end));
            for (const property of REQUIRED_WIRING[match[1]]) {
                if (!new RegExp(`\\b${property}:`).test(body))
                    offenders.push(`${path.relative(shellDir, file)}: `
                        + `${match[1]} is missing ${property}`);
            }
        }
    }
    assert.deepEqual(offenders, [],
        "an unwired hover state cannot clear itself after a missed exit");
});

test("nothing in the bar binds visibility to another item's visibility", () => {
    // `visible` reads back *effective* visibility — the item's own flag ANDed
    // with its parents' — so `visible: child.visible` makes an item depend on
    // itself and latch at false. It looks right for as long as the child starts
    // visible, which is exactly why it shipped: only the modules that turn on
    // later (a track starts, updates appear, a tray icon registers) went
    // missing. Bind to the condition instead, and name it if two things need
    // it — a sibling's `visible` is not a latch today but becomes one the
    // moment the tree is rearranged.
    const offenders = [];
    for (const file of barQmlFiles()) {
        fs.readFileSync(file, "utf8").split("\n").forEach((line, index) => {
            if (/^\s*visible:\s*\w+\.visible\s*$/.test(line))
                offenders.push(`${path.relative(shellDir, file)}:${index + 1}`);
        });
    }
    assert.deepEqual(offenders, []);
});

test("only the bar decides whether a module is on screen", () => {
    // The dividers between grouped modules and the pill around them both read
    // `autoRule`, so a module that hides itself for its own reasons leaves a
    // separator with nothing beside it and a pill with nothing inside it.
    const bar = read("Bar/Bar.qml");
    const rule = bar.match(/function autoRule\(id\)[\s\S]*?\n    \}/)?.[0] ?? "";
    assert.ok(rule !== "", "the bar must still own the auto-rules");
    for (const id of ["media", "weather", "bt", "batt", "updates", "tray"])
        assert.match(rule, new RegExp(`case "${id}":`), `autoRule says nothing about ${id}`);

    const dir = path.join(shellDir, "Bar", "Modules");
    const offenders = [];
    for (const name of fs.readdirSync(dir).filter(f => f.endsWith(".qml"))) {
        const source = fs.readFileSync(path.join(dir, name), "utf8");
        // Top-level `visible:` on the module root, which is what would fight
        // the slot. A `visible:` on something inside it is that thing's own
        // business — a label hidden while compacted, a badge with no count.
        for (const line of topLevel(source).split("\n")) {
            if (/^\s*visible:/.test(line))
                offenders.push(`${name}: ${line.trim()}`);
        }
    }
    assert.deepEqual(offenders, [],
        "a module that hides itself disagrees with the divider beside it");
});

test("no bar chip rests on the fill it hovers to", () => {
    // One ladder for all of them: `restFill` at rest, Theme.chipHover under the
    // pointer, and the same hover fill while the popout is open. A chip resting
    // on the hover value looks permanently hovered — the T3 and usage provider
    // chips shipped that way once and were reported as exactly that.
    const offenders = [];
    for (const file of barQmlFiles()) {
        const lines = fs.readFileSync(file, "utf8").split("\n");
        lines.forEach((line, index) => {
            // The last arm of a colour expression is the resting value.
            if (/^\s*:?\s*Theme\.chipHover\s*$/.test(line)
                    && !/\?/.test(lines[index]))
                offenders.push(`${path.relative(shellDir, file)}:${index + 1}`);
        });
    }
    assert.deepEqual(offenders, [],
        "a chip resting on the hover fill looks permanently hovered");
});

test("nothing in the bar draws a hover state straight off a MouseArea", () => {
    // The point of PointerCheck is that one stale `containsMouse` cannot leave
    // a chip lit, so a colour or a tooltip bound to the raw state defeats it.
    // Feeding PointerCheck itself is the one legitimate read.
    const offenders = [];
    for (const file of barQmlFiles()) {
        if (path.basename(file) === "Bar.qml")
            continue;              // owns the HoverHandler the check reads
        const lines = fs.readFileSync(file, "utf8").split("\n");
        lines.forEach((line, index) => {
            if (/^\s*\/\//.test(line))
                return;
            if (!/\.containsMouse\b|\bmouse\.hovered\b/.test(line))
                return;
            if (/^\s*hovered:/.test(line))
                return;            // the raw opinion, on its way into the check
            offenders.push(`${path.relative(shellDir, file)}:${index + 1}`);
        });
    }
    assert.deepEqual(offenders, []);
});
