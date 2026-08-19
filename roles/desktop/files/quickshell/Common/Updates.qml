pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "ProcHelpers.js" as ProcHelpers
import "UpdatesHelpers.js" as UpdatesHelpers

// Pending system updates: dnf packages and Flatpak refs.
//
// Polling is inherent here — there is nothing to subscribe to — so this is one
// timer, at the interval the module's settings choose, plus a manual refresh
// from the panel. Neither check needs root.
//
// The dnf side is deliberately `--cacheonly`: a refreshing check-update can
// stop to ask whether to import a repository's signing key, and a shell poller
// has no terminal to answer with — it simply hangs. Reading the cache that
// dnf-makecache.timer already keeps warm is both the honest and the cheap
// answer, and it is what the panel's footnote says it is doing.
Singleton {
    id: root

    property int dnfCount: 0
    property int flatpakCount: 0
    property var dnfNames: []
    property var flatpakNames: []
    property bool ran: false
    // A failed first attempt is not a baseline: the first complete result of
    // a session stays silent even if an earlier attempt could not run.
    property bool hasBaseline: false
    property double lastChecked: 0
    property string error: ""

    property bool dnfDone: true
    property bool flatpakDone: true
    readonly property bool busy: !dnfDone || !flatpakDone

    // Results stay private until both commands finish. Publishing each stream
    // as it closes makes total briefly describe a half-completed check and can
    // fire a notification for a state that never existed.
    property var nextDnfNames: []
    property var nextFlatpakNames: []
    property string dnfError: ""
    property string flatpakError: ""
    property bool checkingFlatpak: false
    property bool checkAgain: false
    property bool initialized: false

    readonly property int total: dnfCount + flatpakCount
    readonly property bool flatpakEnabled: Settings.modOpts.updates.flatpak

    // Once the count has been non-zero and then falls to zero, the panel says
    // so rather than pretending nothing was ever pending.
    property bool wasPending: false

    readonly property string summary: {
        if (busy)
            return "Checking…";
        if (error !== "")
            return "Updates unavailable";
        if (total === 0)
            return "All up to date";
        const parts = [];
        if (dnfCount > 0)
            parts.push("dnf " + dnfCount);
        if (flatpakCount > 0)
            parts.push("flatpak " + flatpakCount);
        return parts.join(" · ");
    }

    function checkedLabel() {
        if (lastChecked === 0)
            return "not checked yet";
        const mins = Math.floor((Date.now() - lastChecked) / 60000);
        if (mins < 1)
            return "checked just now";
        if (mins < 60)
            return "checked " + mins + " m ago";
        return "checked " + Math.floor(mins / 60) + " h ago";
    }

    // A first few names for the panel's subtitle, so the two rows say
    // something more useful than a bare count.
    //
    // Deduplicated, because a multiarch package appears once per architecture
    // and "SDL3 · SDL3 · abrt" reads as a bug. The count beside it stays raw:
    // it has to agree with what `dnf upgrade` is about to list.
    function namesLabel(list, count) {
        const unique = [];
        for (const name of list) {
            if (unique.indexOf(name) === -1)
                unique.push(name);
            if (unique.length === 3)
                break;
        }
        if (unique.length === 0)
            return count > 0 ? count + " pending" : "";
        const shown = unique.join(" · ");
        return unique.length < count ? shown + " and more" : shown;
    }

    function check() {
        if (busy) {
            checkAgain = true;
            return;
        }
        checkAgain = false;
        error = "";
        dnfError = "";
        flatpakError = "";
        nextDnfNames = [];
        nextFlatpakNames = [];
        checkingFlatpak = flatpakEnabled;
        dnfDone = false;
        flatpakDone = !checkingFlatpak;
        dnfProc.running = true;
        if (checkingFlatpak)
            flatpakProc.running = true;
    }

    function finishDnf(exitCode, body, errText) {
        if (exitCode === 0 || exitCode === 100) {
            nextDnfNames = UpdatesHelpers.dnfNames(body);
        } else {
            dnfError = ProcHelpers.commandError("dnf check-update", exitCode, errText,
                ({ 124: "dnf check-update timed out" }));
            console.warn("update check:", dnfError);
        }
        dnfDone = true;
        finishCheck();
    }

    function finishFlatpak(exitCode, body, errText) {
        if (exitCode === 0) {
            nextFlatpakNames = UpdatesHelpers.flatpakNames(body);
        } else {
            flatpakError = ProcHelpers.commandError("flatpak update check", exitCode, errText,
                ({ 124: "Flatpak update check timed out" }));
            console.warn("update check:", flatpakError);
        }
        flatpakDone = true;
        finishCheck();
    }

    function finishCheck() {
        if (!dnfDone || !flatpakDone)
            return;

        const previousTotal = total;
        const nextDnfCount = dnfError === "" ? nextDnfNames.length : dnfCount;
        const nextFlatpakCount = !checkingFlatpak ? 0
            : flatpakError === "" ? nextFlatpakNames.length : flatpakCount;
        const nextTotal = nextDnfCount + nextFlatpakCount;
        const errors = [dnfError, flatpakError].filter(value => value !== "");
        const complete = errors.length === 0;

        if (dnfError === "") {
            dnfNames = nextDnfNames;
            dnfCount = nextDnfCount;
        }
        if (!checkingFlatpak || flatpakError === "") {
            flatpakNames = checkingFlatpak ? nextFlatpakNames : [];
            flatpakCount = nextFlatpakCount;
        }

        error = errors.join(" · ");
        lastChecked = Date.now();
        ran = true;
        if (nextTotal > 0)
            wasPending = true;

        if (UpdatesHelpers.shouldNotify(complete, hasBaseline, previousTotal, nextTotal,
                Settings.modOpts.updates.notify)) {
            Quickshell.execDetached(["notify-send", "--app-name=Updates",
                nextTotal + (nextTotal === 1 ? " update ready" : " updates ready"),
                summary]);
        }
        if (complete)
            hasBaseline = true;

        if (checkAgain)
            Qt.callLater(root.check);
    }

    // The upgrade itself is interactive — it asks for a password and prints
    // a transaction to approve — so it runs in a terminal rather than being
    // swallowed by the shell.
    function run() {
        Quickshell.execDetached(["kitty", "--title", "System updates", "sh", "-c",
            "sudo dnf upgrade --refresh"
            + (root.flatpakEnabled ? "; flatpak update" : "")
            + "; printf '\\nDone. Press enter to close.'; read _"]);
        Popouts.close();
        // The transaction takes as long as it takes; re-check on a slow beat
        // afterwards so the chip clears itself once it has finished.
        recheck.restart();
    }

    Timer {
        id: recheck
        interval: 60000
        repeat: true
        property int ticks: 0
        onTriggered: {
            root.check();
            if (++ticks > 15) {
                ticks = 0;
                stop();
            }
        }
        onRunningChanged: {
            if (running)
                ticks = 0;
        }
    }

    Timer {
        interval: Math.max(10, Settings.modOpts.updates.pollMins) * 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.check()
    }

    // dnf check-update lists one package per line as "name.arch  version  repo"
    // under a plain-text section heading. Exit 100 is the "there are updates"
    // status, exit 0 means none, anything else is a real failure.
    Process {
        id: dnfProc
        property string body: ""
        property string errText: ""
        property bool exitSeen: false
        property int lastExit: 0

        command: ["timeout", "45s", "env", "LC_ALL=C", "dnf", "--quiet",
            "--cacheonly", "check-update"]

        stdout: StdioCollector {
            onStreamFinished: dnfProc.body = text
        }

        stderr: StdioCollector {
            onStreamFinished: dnfProc.errText = text
        }

        onExited: (exitCode, exitStatus) => {
            dnfProc.exitSeen = true;
            dnfProc.lastExit = exitCode;
        }
        onRunningChanged: {
            if (running) {
                body = "";
                errText = "";
                exitSeen = false;
                lastExit = 0;
            } else {
                root.finishDnf(exitSeen ? lastExit : ProcHelpers.NOT_STARTED, body, errText);
            }
        }
    }

    Process {
        id: flatpakProc
        property string body: ""
        property string errText: ""
        property bool exitSeen: false
        property int lastExit: 0

        command: ["timeout", "45s", "env", "LC_ALL=C", "flatpak", "remote-ls",
            "--updates", "--app", "--columns=name"]

        stdout: StdioCollector {
            onStreamFinished: flatpakProc.body = text
        }

        stderr: StdioCollector {
            onStreamFinished: flatpakProc.errText = text
        }

        onExited: (exitCode, exitStatus) => {
            flatpakProc.exitSeen = true;
            flatpakProc.lastExit = exitCode;
        }
        onRunningChanged: {
            if (running) {
                body = "";
                errText = "";
                exitSeen = false;
                lastExit = 0;
            } else {
                root.finishFlatpak(exitSeen ? lastExit : ProcHelpers.NOT_STARTED,
                    body, errText);
            }
        }
    }

    Component.onCompleted: initialized = true
    onFlatpakEnabledChanged: {
        if (initialized)
            check();
    }
}
