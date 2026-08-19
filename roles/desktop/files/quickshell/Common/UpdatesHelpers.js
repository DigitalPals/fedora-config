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

var exported = {
    dnfNames: dnfNames,
    flatpakNames: flatpakNames,
    shouldNotify: shouldNotify
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
