// Pure parsing and transition rules for Common/Updates.qml. Keeping these free
// of Qt APIs makes the parts fed by command output executable under Node.

function dnfNames(body) {
    var names = [];
    String(body || "").split("\n").forEach(function (line) {
        // Section headings carry no columns and continuation lines are
        // indented. A package row begins with name.arch, followed by its
        // version and repository.
        var match = line.match(/^([A-Za-z0-9][^\s]*)\.[a-z0-9_]+\s+\S+\s+\S/);
        if (match)
            names.push(match[1]);
    });
    return names;
}

function flatpakNames(body) {
    return String(body || "").split("\n")
        .map(function (line) { return line.trim(); })
        .filter(function (line) { return line !== ""; });
}

// Only a complete zero -> positive transition after a known baseline is news.
// A failed first attempt must not turn the first successful snapshot into a
// notification for updates that may have been pending before login.
function shouldNotify(complete, hasBaseline, previousTotal, nextTotal, enabled) {
    return !!complete && !!hasBaseline && previousTotal === 0
        && nextTotal > 0 && !!enabled;
}

// ---- native run parsing ----------------------------------------------------
// The in-shell upgrade streams the same non-TTY dnf5/flatpak output the update
// script's dashboard greps; these turn its lines into typeset feed rows.

// Architecture suffixes dnf appends to a transaction element.
var NEVRA_ARCHES = ["x86_64", "noarch", "i686", "aarch64", "riscv64",
    "ppc64le", "s390x"];

// Transaction verbs that name a package, and the feed verb each becomes.
// Non-package bracketed lines (Prepare, Verify, scriptlets) still advance the
// progress counter but add no row; so does Cleanup, which would otherwise
// shadow every upgrade with a second row for the outgoing version.
var DNF_RUN_VERBS = {
    "Upgrading": "up",
    "Installing": "add",
    "Reinstalling": "up",
    "Downgrading": "down",
    "Removing": "del",
    "Erasing": "del",
    "Replacing": "del"
};

// "kernel-core-0:7.1.9-200.fc44.x86_64" -> { name, version }. NEVRA splits
// from the right: release after the last dash, version after the one before
// it, the optional epoch folded away since nobody reads "0:" in a feed.
function splitNevra(text) {
    var value = String(text || "").trim();
    for (var i = 0; i < NEVRA_ARCHES.length; i++) {
        var suffix = "." + NEVRA_ARCHES[i];
        if (value.length > suffix.length
                && value.slice(-suffix.length) === suffix) {
            value = value.slice(0, -suffix.length);
            break;
        }
    }
    var release = value.lastIndexOf("-");
    var version = release > 0 ? value.lastIndexOf("-", release - 1) : -1;
    if (version <= 0)
        return { name: value, version: "" };
    return {
        name: value.slice(0, version),
        version: value.slice(version + 1).replace(/^[0-9]+:/, "")
    };
}

// One line of `dnf upgrade` output. Null for anything outside the running
// transaction; a bare { cur, total } for a transaction step that names no
// package, so callers can advance progress without drawing a row.
function parseDnfRunLine(line) {
    var match = String(line || "").replace(/\r/g, "")
        .match(/^\[ *([0-9]+)\/([0-9]+)\] +(.*)$/);
    if (!match)
        return null;
    var out = {
        cur: parseInt(match[1], 10),
        total: parseInt(match[2], 10),
        verb: "",
        name: "",
        version: ""
    };
    var action = match[3].trim().match(/^([A-Za-z]+):? +(\S+)/);
    if (action && DNF_RUN_VERBS.hasOwnProperty(action[1])) {
        var nevra = splitNevra(action[2]);
        out.verb = DNF_RUN_VERBS[action[1]];
        out.name = nevra.name;
        out.version = nevra.version;
    }
    return out;
}

// Application ids read as their most distinctive segment: org.signal.Signal
// is "Signal", but com.spotify.Client must not become "Client".
var FLATPAK_GENERIC_TAILS = ["client", "app", "desktop"];

function flatpakRefName(id) {
    var parts = String(id || "").split(".").filter(function (part) {
        return part !== "";
    });
    if (parts.length === 0)
        return String(id || "");
    var pick = parts[parts.length - 1];
    if (parts.length > 1
            && FLATPAK_GENERIC_TAILS.indexOf(pick.toLowerCase()) !== -1)
        pick = parts[parts.length - 2];
    return pick.charAt(0).toUpperCase() + pick.slice(1);
}

// One line of `flatpak update --noninteractive` output. "planned" rows are
// the numbered transaction table (their count is the app total); "op" rows
// are the work actually happening.
function parseFlatpakRunLine(line) {
    var text = String(line || "").replace(/\r/g, "");
    var op = text.match(/^(Updating|Installing|Uninstalling) +(app|runtime)\/([^\/\s]+)/);
    if (op) {
        return {
            kind: "op",
            verb: op[1] === "Updating" ? "up"
                : op[1] === "Installing" ? "add" : "del",
            runtime: op[2] === "runtime",
            name: flatpakRefName(op[3])
        };
    }
    var planned = text.match(/^ *([0-9]+)\.[ \t]/);
    if (planned)
        return { kind: "planned", n: parseInt(planned[1], 10) };
    return null;
}

// Combined chip percentage across both package streams; -1 until either
// stream has a real denominator, which the chip renders as indeterminate.
function runPercent(dnfCur, dnfTotal, fpCur, fpTotal) {
    var total = Math.max(0, dnfTotal || 0) + Math.max(0, fpTotal || 0);
    if (total <= 0)
        return -1;
    var cur = Math.min(dnfCur || 0, dnfTotal || 0)
        + Math.min(fpCur || 0, fpTotal || 0);
    return Math.max(0, Math.min(100, Math.round(cur * 100 / total)));
}

// The version worth a reboot hint, short enough to say out loud: the first
// kernel the transaction installed, as "7.1.9" rather than the full NEVRA.
function kernelHint(name, verb, version) {
    if (name !== "kernel" && name !== "kernel-core")
        return "";
    if (verb !== "add" && verb !== "up")
        return "";
    return String(version || "").split("-")[0];
}

// The line a failure banner leads with: the last line of the tail that names
// a problem, clipped so a stack of context cannot take over the panel.
function failureHeadline(lines) {
    var list = Array.isArray(lines) ? lines : [];
    for (var i = list.length - 1; i >= 0; i--) {
        var line = String(list[i]).trim();
        if (/error|failed|cannot|unable|not authorized|no space/i.test(line))
            return line.length > 96 ? line.slice(0, 95) + "…" : line;
    }
    return "";
}

// Log directory stamp, matching the update script's `date +%Y%m%d-%H%M%S` so
// both entry points shelve their logs the same way.
function logStamp(date) {
    function pad(value) {
        return (value < 10 ? "0" : "") + value;
    }
    return "" + date.getFullYear() + pad(date.getMonth() + 1)
        + pad(date.getDate()) + "-" + pad(date.getHours())
        + pad(date.getMinutes()) + pad(date.getSeconds());
}

var exported = {
    dnfNames: dnfNames,
    flatpakNames: flatpakNames,
    shouldNotify: shouldNotify,
    splitNevra: splitNevra,
    parseDnfRunLine: parseDnfRunLine,
    flatpakRefName: flatpakRefName,
    parseFlatpakRunLine: parseFlatpakRunLine,
    runPercent: runPercent,
    kernelHint: kernelHint,
    failureHeadline: failureHeadline,
    logStamp: logStamp
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
