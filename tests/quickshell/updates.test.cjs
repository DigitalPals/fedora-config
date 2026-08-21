const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir, load } = require("./shell.cjs");

const H = load("UpdatesHelpers.js");

function read(relative) {
    return fs.readFileSync(path.join(shellDir, relative), "utf8");
}

test("dnf output keeps real package rows and their raw multiarch count", () => {
    const output = [
        "Updating and loading repositories:",
        "Repositories loaded.",
        "SDL3.i686                 3.2.22-1.fc44 updates",
        "SDL3.x86_64               3.2.22-1.fc44 updates",
        "python3-foo+bar.noarch     1.4-2.fc44    updates",
        "  a continuation that is not a package"
    ].join("\n");

    assert.deepEqual(H.dnfNames(output), ["SDL3", "SDL3", "python3-foo+bar"]);
    assert.deepEqual(H.dnfNames(""), []);
});

test("Flatpak output drops blank rows without changing application names", () => {
    assert.deepEqual(H.flatpakNames("Firefox\n  Spotify  \n\n"),
        ["Firefox", "Spotify"]);
    assert.deepEqual(H.flatpakNames(undefined), []);
});

test("only a complete post-baseline zero-to-positive transition notifies", () => {
    assert.equal(H.shouldNotify(true, true, 0, 3, true), true);
    assert.equal(H.shouldNotify(true, false, 0, 3, true), false,
        "the first successful snapshot establishes the baseline silently");
    assert.equal(H.shouldNotify(false, true, 0, 3, true), false,
        "a partial failure cannot announce a half-result");
    assert.equal(H.shouldNotify(true, true, 2, 3, true), false,
        "a count that merely grows is not a new update event");
    assert.equal(H.shouldNotify(true, true, 0, 3, false), false);
});

test("table sections map to feed verbs and reject prose", () => {
    assert.equal(H.dnfSection("Upgrading:"), "up");
    assert.equal(H.dnfSection("Installing dependencies:"), "add");
    assert.equal(H.dnfSection("Removing unused dependencies:"), "del");
    assert.equal(H.dnfSection("Transaction Summary:"), null);
    assert.equal(H.dnfSection(" firefox   x86_64 0:154.0-3.fc44 updates 287.1 MiB"),
        null);
    assert.equal(H.dnfSection(""), null);
});

test("table rows carry the full untruncated name and version", () => {
    // Verbatim lines from a real fc44 transaction table.
    assert.deepEqual(H.dnfTableRow(
        " gnome-shell-extension-launch-new-instance             noarch 0:50.3-1.fc44      updates                            1.4 KiB"),
        { name: "gnome-shell-extension-launch-new-instance", arch: "noarch",
            evr: "0:50.3-1.fc44", version: "50.3-1.fc44" });
    assert.deepEqual(H.dnfTableRow(
        " vim-minimal                                           x86_64 2:9.2.967-1.fc44   updates                            1.8 MiB").version,
        "9.2.967-1.fc44", "the epoch is for matching, not for reading");
    assert.equal(H.dnfTableRow(
        "   replacing firefox                                   x86_64 0:153.0.3-1.fc44   updates                          282.0 MiB"),
        null, "outgoing versions are continuations, not packages");
    assert.equal(H.dnfTableRow("Transaction Summary:"), null);
    assert.equal(H.dnfTableRow(""), null);
});

test("bracketed progress lines advance the counter; verbs carry dnf's clipped token", () => {
    assert.deepEqual(H.parseDnfRunLine(
        "[11/58] Upgrading less-0:704-4.fc44.x86 100% |  29.5 MiB/s | 483.2 KiB |  00m00s"),
        { cur: 11, total: 58, verb: "up", token: "less-0:704-4.fc44.x86" });
    assert.deepEqual(H.parseDnfRunLine(
        "[53/58] Removing tmux-0:3.7b-2.fc44.x86 100% | 636.0   B/s |  14.0   B |  00m00s"),
        { cur: 53, total: 58, verb: "del", token: "tmux-0:3.7b-2.fc44.x86" });
    assert.deepEqual(H.parseDnfRunLine(
        "[10/28] less-0:704-4.fc44.x86_64        100% |   2.2 MiB/s | 227.8 KiB |  00m00s"),
        { cur: 10, total: 28, verb: "", token: "" },
        "download lines are progress only");
    assert.equal(H.parseDnfRunLine(
        "[ 1/58] Verify package files            100% |  51.0   B/s |  28.0   B |  00m01s").verb,
        "", "aux steps keep the counter without naming a package");
    assert.equal(H.parseDnfRunLine("Running transaction"), null);
    assert.equal(H.parseDnfRunLine(""), null);
});

test("clipped tokens find their table row, and only theirs", () => {
    assert.ok(H.rowMatchesToken("less", "0:704-4.fc44", "less-0:704-4.fc"),
        "a token cut inside the evr still matches");
    assert.ok(H.rowMatchesToken("less", "0:704-4.fc44", "less-0:704-4.fc44.x86"),
        "a token extending into the arch still matches");
    assert.ok(!H.rowMatchesToken("less-color", "0:704-4.fc44", "less-0:704-4.fc44.x86"),
        "a longer-named sibling must not claim the token");
    assert.ok(!H.rowMatchesToken("less", "0:704-4.fc44", "less-color-0:704-4.fc"),
        "nor the reverse");
    assert.ok(!H.rowMatchesToken("tmux", "0:3.7c-1.fc44", "tmux-0:3.7b-2.fc44.x86"),
        "cleanup of the outgoing version matches no incoming row");
    assert.ok(!H.rowMatchesToken("less", "0:704-4.fc44", ""));
});

test("flatpak lines separate the plan from the work and name apps sensibly", () => {
    assert.deepEqual(H.parseFlatpakRunLine(" 1.\torg.signal.Signal"),
        { kind: "planned", n: 1 });
    assert.deepEqual(H.parseFlatpakRunLine("Updating app/org.signal.Signal/x86_64/stable"),
        { kind: "op", verb: "up", runtime: false, name: "Signal" });
    assert.deepEqual(H.parseFlatpakRunLine("Installing runtime/org.freedesktop.Platform/x86_64/24.08"),
        { kind: "op", verb: "add", runtime: true, name: "Platform" });
    assert.equal(H.parseFlatpakRunLine("Updating app/com.spotify.Client/x86_64/stable").name,
        "Spotify", "a generic tail segment yields to the vendor segment");
    assert.equal(H.parseFlatpakRunLine("Looking for updates…"), null);
});

test("the chip percentage stays honest across both streams", () => {
    assert.equal(H.runPercent(0, 0, 0, 0), -1,
        "no denominator yet means indeterminate, not 0%");
    assert.equal(H.runPercent(76, 120, 0, 0), 63);
    assert.equal(H.runPercent(60, 120, 1, 2), 50);
    assert.equal(H.runPercent(500, 120, 9, 2), 100,
        "overshoot clamps rather than exceeding 100");
});

test("only an incoming kernel earns the reboot hint", () => {
    assert.equal(H.kernelHint("kernel-core", "add", "7.1.9-200.fc44"), "7.1.9");
    assert.equal(H.kernelHint("kernel", "up", "7.1.9-200.fc44"), "7.1.9");
    assert.equal(H.kernelHint("kernel-core", "del", "7.1.4-100.fc44"), "",
        "removing the old kernel is not news");
    assert.equal(H.kernelHint("kernel-headers", "up", "7.1.9-200.fc44"), "");
});

test("the failure banner leads with the last line that names a problem", () => {
    assert.equal(H.failureHeadline([
        "Running transaction check…",
        "GPG signature check failed: mesa-dri-drivers-25.3.2-1.fc44",
        "Transaction aborted."
    ]), "GPG signature check failed: mesa-dri-drivers-25.3.2-1.fc44");
    assert.equal(H.failureHeadline(["all quiet"]), "");
    assert.equal(H.failureHeadline([]), "");
    assert.equal(H.failureHeadline(["Error: " + "x".repeat(200)]).length, 96,
        "one runaway line cannot take over the banner");
});

test("log stamps match the update script's shelf naming", () => {
    assert.equal(H.logStamp(new Date(2026, 7, 21, 14, 32, 5)), "20260821-143205");
    assert.equal(H.logStamp(new Date(2026, 0, 1, 0, 0, 0)), "20260101-000000");
});

test("the QML coordinator settles both commands, including start failures", () => {
    const updates = read("Common/Updates.qml");
    const popover = read("Popovers/UpdatesPopover.qml");

    assert.match(updates, /readonly property bool busy: !dnfDone \|\| !flatpakDone/);
    assert.match(updates, /function finishCheck\(\) \{\s*if \(!dnfDone \|\| !flatpakDone\)\s*return;/);
    assert.equal((updates.match(/ProcHelpers\.NOT_STARTED/g) || []).length, 5,
        "check and run commands all need the no-exited-signal fallback, and "
        + "the failure banner names the could-not-start case");
    assert.equal((updates.match(/onRunningChanged:/g) || []).length >= 3, true,
        "both processes and the recheck timer should have completion handling");
    assert.doesNotMatch(updates, /onTotalChanged:/,
        "intermediate per-process totals must not drive notifications");
    assert.match(updates, /command: \["timeout", "45s"/,
        "a background poll must have a finite upper bound");
    assert.match(popover, /Accessible\.name:[\s\S]{0,100}?Check for updates/);
    assert.match(popover, /onClicked:[\s\S]{0,100}?Updates\.check\(\)/);
});
