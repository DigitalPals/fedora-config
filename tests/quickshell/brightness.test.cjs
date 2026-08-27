const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

function read(relative) {
    return fs.readFileSync(path.join(shellDir, relative), "utf8");
}

// Which screen is in front of you decides whether brightness is a sysfs
// backlight or an Apple display on USB HID. brightness-control is where that
// decision lives; a view or singleton that reaches for a tool itself gets it
// wrong the moment the laptop is docked, and gets it wrong silently — it
// moves the closed lid's panel and reads back that panel's level.
test("the shell never picks a brightness backend for itself", () => {
    const walk = dir => fs.readdirSync(dir, { withFileTypes: true })
        .flatMap(entry => {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory())
                return ["assets", "scripts"].includes(entry.name) ? [] : walk(full);
            return /\.(?:qml|js)$/.test(entry.name) ? [full] : [];
        });

    for (const file of walk(shellDir)) {
        const label = path.relative(shellDir, file).split(path.sep).join("/");
        assert.doesNotMatch(fs.readFileSync(file, "utf8"),
            /"(?:brightnessctl|asdcontrol)"/,
            `${label} must go through brightness-control, not a backend directly`);
    }
});

test("SysInfo reads and writes brightness through brightness-control", () => {
    const sys = read("Common/SysInfo.qml");

    assert.match(sys,
        /readonly property string brightnessTool:\s*\n?\s*Quickshell\.env\("HOME"\) \+ "\/\.local\/bin\/brightness-control"/);
    assert.match(sys, /command:\s*\[root\.brightnessTool, "get"\]/,
        "the reading must come from the same helper that writes it");
    assert.match(sys, /\[root\.brightnessTool, "set",/,
        "the slider must write an absolute percent");

    // The old sysfs fast path read the laptop backlight whatever was plugged
    // in. It is not a fast path worth having if the number is the wrong one.
    assert.doesNotMatch(sys, /class\/backlight|max_brightness/,
        "no direct sysfs backlight reads may come back");

    // A drag emits a value on every mouse move; one process per move is not
    // survivable when each costs tens of milliseconds.
    const setter = sys.slice(sys.indexOf("function setBrightness"),
        sys.indexOf("Process {", sys.indexOf("function setBrightness")));
    assert.match(setter, /brightness = pct/,
        "the reading must follow the pointer so the slider stays live");
    assert.match(setter, /brightnessWrite\.restart\(\)/,
        "the write itself must be coalesced onto the last value");

    // A read that overtakes an unlanded write drags the slider backwards.
    assert.match(sys,
        /function refreshBrightness\(\) \{[\s\S]{0,200}?brightnessWrite\.running[\s\S]{0,80}?brightnessSettle\.running/);
});

test("brightness-control keeps the verbs its callers use", () => {
    const script = fs.readFileSync(path.resolve(shellDir,
        "../../../dotfiles/templates/brightness-control.j2"), "utf8");
    const bindings = fs.readFileSync(path.resolve(shellDir,
        "../bindings.lua"), "utf8");

    for (const verb of ["up", "down", "set", "get"])
        assert.ok(script.includes(verb), `brightness-control must handle ${verb}`);
    // The keybinds are the other caller, and they predate the slider.
    assert.match(bindings, /brightness-control up 5/);
    assert.match(bindings, /brightness-control down 5/);
});
