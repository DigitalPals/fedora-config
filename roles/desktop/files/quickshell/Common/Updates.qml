pragma Singleton
import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import "ProcHelpers.js" as ProcHelpers
import "UpdatesHelpers.js" as UpdatesHelpers

// Pending system updates: dnf packages and Flatpak refs — and the native run
// that installs them without leaving the shell.
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
//
// The run itself streams here rather than into a terminal. Root comes from
// `sudo -n` where the wheel sudoers drop-in makes that silent, else `pkexec`,
// whose dialog is the polkit agent's native one. State lives in this
// singleton, never in the popover: the panel can close and reopen mid-run and
// the transaction neither notices nor cares.
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
    property int checkFailureCount: 0
    property string lastLoggedCheckError: ""

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
        // A poll firing mid-transaction would read the cache while dnf is
        // rewriting the installed set; whatever it said would be wrong by the
        // time it landed. finishRun schedules the recount instead.
        if (runActive)
            return;
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

    // Automatic work waits for NetworkManager's global connected state.
    // Manual refresh remains an explicit attempt, even on a network whose
    // connectivity check is conservative or unavailable.
    function automaticCheck(resetRetries) {
        if (!NetworkStatus.online)
            return;
        if (resetRetries)
            checkFailureCount = 0;
        check();
    }

    function logCheckError(reason) {
        if (reason === lastLoggedCheckError)
            return;
        console.warn("update check:", reason);
        lastLoggedCheckError = reason;
    }

    function finishDnf(exitCode, body, errText) {
        if (exitCode === 0 || exitCode === 100) {
            nextDnfNames = UpdatesHelpers.dnfNames(body);
        } else {
            dnfError = ProcHelpers.commandError("dnf check-update", exitCode, errText,
                ({ 124: "dnf check-update timed out" }));
            logCheckError(dnfError);
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
            logCheckError(flatpakError);
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
        if (complete) {
            hasBaseline = true;
            checkFailureCount = 0;
            lastLoggedCheckError = "";
        } else {
            checkFailureCount++;
        }

        if (checkAgain)
            Qt.callLater(root.check);
    }

    // ---- the native run ---------------------------------------------------
    // idle | running | done | failed. `done` clears once the user has opened
    // and closed the finished panel (or after a quiet timeout); `failed`
    // stays until dismissed or retried, so an unattended failure cannot
    // vanish. The feed is a ListModel so the transcript appends in place —
    // reassigning a var array would reset the view and lose scrollback.
    property string runState: "idle"
    readonly property bool runActive: runState === "running"
    property double runStartedAt: 0
    property double runFinishedAt: 0
    property int runElapsed: 0
    property int runDuration: 0
    property string runStamp: ""
    // resolving -> downloading -> installing, keyed off dnf's own milestones.
    property string dnfPhase: "resolving"
    // The table section currently streaming in; "" outside the table.
    property string tableVerb: ""
    // Feed index of the row the transaction most recently completed.
    property int lastDoneIndex: -1
    property int dnfCur: 0
    property int dnfTotal: 0
    property int fpCur: 0
    property int fpTotal: 0
    property bool runDnfDone: true
    property bool runFpDone: true
    property int runDnfRc: 0
    property int runFpRc: 0
    property int upCount: 0
    property int addCount: 0
    property int delCount: 0
    property int appCount: 0
    property var topNames: []
    property string kernelPending: ""
    property string failHeadline: ""
    property var failTail: []
    property var rawTail: []
    property string fpWarning: ""
    // The finished panel has been opened; closing it then retires `done`.
    property bool runSeen: false

    readonly property int runPercent: UpdatesHelpers.runPercent(
        dnfCur, dnfTotal, fpCur, fpTotal)
    readonly property int runPkgCount: upCount + addCount + delCount
    readonly property string runLogLabel: "xps-update/logs/" + runStamp

    ListModel {
        id: feedModel
    }
    readonly property ListModel feed: feedModel

    function run() {
        if (runActive)
            return;
        feedModel.clear();
        dnfCur = 0;
        dnfTotal = 0;
        fpCur = 0;
        fpTotal = 0;
        upCount = 0;
        addCount = 0;
        delCount = 0;
        appCount = 0;
        topNames = [];
        kernelPending = "";
        failHeadline = "";
        failTail = [];
        rawTail = [];
        fpWarning = "";
        runSeen = false;
        runDnfRc = 0;
        runFpRc = 0;
        runStamp = UpdatesHelpers.logStamp(new Date());
        runStartedAt = Date.now();
        runElapsed = 0;
        dnfPhase = "resolving";
        tableVerb = "";
        lastDoneIndex = -1;
        runDnfDone = false;
        runFpDone = !flatpakEnabled;
        runState = "running";
        doneClear.stop();
        runDnfProc.running = true;
        if (flatpakEnabled)
            runFpProc.running = true;
    }

    function dnfLine(line) {
        const text = String(line).replace(/\r/g, "");
        if (text.trim() !== "")
            rawTail = rawTail.concat([text]).slice(-10);

        // The resolved table is the one place dnf prints every package's
        // full name and version, so its rows build the feed; the bracketed
        // progress lines below are column-clipped by dnf and only advance
        // the counter and tick rows off.
        const section = UpdatesHelpers.dnfSection(text);
        if (section !== null) {
            tableVerb = section;
            return;
        }
        if (tableVerb !== "") {
            const row = UpdatesHelpers.dnfTableRow(text);
            if (row !== null) {
                feedModel.append({ tag: "dnf", verb: tableVerb, name: row.name,
                    ver: row.version, evr: row.evr, done: false });
                if (tableVerb === "up")
                    upCount++;
                else if (tableVerb === "del")
                    delCount++;
                else
                    addCount++;
                if (kernelPending === "")
                    kernelPending = UpdatesHelpers.kernelHint(row.name,
                        tableVerb, row.version);
                if (tableVerb !== "del" && topNames.length < 3
                        && topNames.indexOf(row.name) === -1)
                    topNames = topNames.concat([row.name]);
                return;
            }
            // Any other column-0 line ("Transaction Summary:") closes the
            // section; the "   replacing …" continuations sit deeper and do
            // not, so an interleaved outgoing version cannot end the table.
            if (/^\S/.test(text))
                tableVerb = "";
        }

        if (text === "Running transaction") {
            dnfPhase = "installing";
            dnfCur = 0;
            dnfTotal = 0;
            return;
        }

        const step = UpdatesHelpers.parseDnfRunLine(text);
        if (step === null)
            return;
        if (dnfPhase === "resolving")
            dnfPhase = "downloading";
        dnfCur = step.cur;
        dnfTotal = step.total;
        if (step.token === "")
            return;
        // Cleanup of a replaced version carries the outgoing evr and matches
        // nothing here — progress moves, the feed stays truthful.
        for (let i = 0; i < feedModel.count; i++) {
            const entry = feedModel.get(i);
            if (entry.tag !== "dnf" || entry.done)
                continue;
            if (UpdatesHelpers.rowMatchesToken(entry.name, entry.evr,
                    step.token)) {
                feedModel.setProperty(i, "done", true);
                lastDoneIndex = i;
                break;
            }
        }
    }

    function fpLine(line) {
        const parsed = UpdatesHelpers.parseFlatpakRunLine(String(line));
        if (parsed === null)
            return;
        if (parsed.kind === "planned") {
            fpTotal = Math.max(fpTotal, parsed.n);
            return;
        }
        feedModel.append({ tag: "fpk", verb: parsed.verb, name: parsed.name,
            ver: "", evr: "", done: true });
        lastDoneIndex = feedModel.count - 1;
        if (!parsed.runtime) {
            fpCur = Math.min(fpCur + 1, Math.max(fpTotal, fpCur + 1));
            appCount++;
        }
    }

    function finishRunDnf(exitCode) {
        runDnfRc = exitCode;
        runDnfDone = true;
        finishRun();
    }

    function finishRunFp(exitCode) {
        runFpRc = exitCode;
        runFpDone = true;
        finishRun();
    }

    function finishRun() {
        if (!runDnfDone || !runFpDone || !runActive)
            return;
        runFinishedAt = Date.now();
        runDuration = Math.round((runFinishedAt - runStartedAt) / 1000);
        if (runDnfRc !== 0) {
            failTail = rawTail;
            failHeadline = UpdatesHelpers.failureHeadline(rawTail);
            if (failHeadline === "")
                failHeadline = runDnfRc === 126 || runDnfRc === 127
                    ? "Authorization dismissed"
                    : runDnfRc === ProcHelpers.NOT_STARTED
                    ? "dnf could not be started"
                    : "dnf exited with status " + runDnfRc;
            runState = "failed";
        } else {
            // A Flathub hiccup should not turn a completed system upgrade
            // into a failure banner; it gets a warning line instead.
            if (flatpakEnabled && runFpRc !== 0)
                fpWarning = "flatpak update failed — see the log";
            runState = "done";
            doneClear.restart();
        }
        // The counts the panel shows must agree with what is now installed.
        recheck.restart();
        Qt.callLater(root.check);
    }

    function dismissRun() {
        runState = "idle";
        runSeen = false;
        doneClear.stop();
    }

    // Raw transcript, in the pager everyone already has. The log file is the
    // one place the full unparsed output survives, so the escape hatch opens
    // it rather than re-rendering it.
    function openLog(file) {
        Quickshell.execDetached(["kitty", "--title", "Update log", "bash",
            "-c", "exec less -R \"${XDG_STATE_HOME:-$HOME/.local/state}/"
            + "xps-update/logs/" + runStamp + "/" + file + "\""]);
    }

    Timer {
        interval: 1000
        running: root.runActive
        repeat: true
        onTriggered: root.runElapsed =
            Math.round((Date.now() - root.runStartedAt) / 1000)
    }

    // An unvisited ✓ should not sit in the bar all afternoon: after a quiet
    // quarter hour the result retires itself and the auto rule tucks the
    // module away. The full log keeps the story.
    Timer {
        id: doneClear
        interval: 15 * 60000
        onTriggered: {
            if (root.runState === "done")
                root.dismissRun();
        }
    }

    // Opening the finished panel is the acknowledgement; the close after it
    // retires the result. A failure never self-acknowledges — dismiss and
    // retry are explicit actions in the panel.
    Connections {
        target: Popouts

        function onChanged() {
            if (Popouts.open && Popouts.currentName === "updates") {
                if (root.runState === "done")
                    root.runSeen = true;
            } else if (!Popouts.open && root.runSeen
                    && root.runState === "done") {
                root.dismissRun();
            }
        }
    }

    // Root through the silent path when the wheel drop-in provides it, else
    // pkexec and the polkit agent's dialog. Output tees into the same log
    // shelf the ./update script uses, and the pipefail keeps dnf's own exit
    // status through the tee.
    Process {
        id: runDnfProc
        property bool exitSeen: false
        property int lastExit: 0

        command: ["bash", "-c",
            "set -o pipefail; "
            + "d=\"${XDG_STATE_HOME:-$HOME/.local/state}/xps-update/logs/"
            + root.runStamp + "\"; mkdir -p \"$d\"; "
            + "if sudo -n true 2>/dev/null; then auth='sudo -n'; "
            + "else auth='pkexec'; fi; "
            + "$auth dnf -y upgrade --refresh 2>&1 | tee \"$d/dnf.log\""]

        stdout: SplitParser {
            onRead: data => root.dnfLine(data)
        }

        onExited: (exitCode, exitStatus) => {
            runDnfProc.exitSeen = true;
            runDnfProc.lastExit = exitCode;
        }
        onRunningChanged: {
            if (running) {
                exitSeen = false;
                lastExit = 0;
            } else {
                root.finishRunDnf(exitSeen ? lastExit : ProcHelpers.NOT_STARTED);
            }
        }
    }

    Process {
        id: runFpProc
        property bool exitSeen: false
        property int lastExit: 0

        command: ["bash", "-c",
            "set -o pipefail; "
            + "d=\"${XDG_STATE_HOME:-$HOME/.local/state}/xps-update/logs/"
            + root.runStamp + "\"; mkdir -p \"$d\"; "
            + "if sudo -n true 2>/dev/null; then auth='sudo -n'; else auth=''; fi; "
            + "$auth flatpak update --system --noninteractive 2>&1 "
            + "| tee \"$d/flatpak.log\""]

        stdout: SplitParser {
            onRead: data => root.fpLine(data)
        }

        onExited: (exitCode, exitStatus) => {
            runFpProc.exitSeen = true;
            runFpProc.lastExit = exitCode;
        }
        onRunningChanged: {
            if (running) {
                exitSeen = false;
                lastExit = 0;
            } else {
                root.finishRunFp(exitSeen ? lastExit : ProcHelpers.NOT_STARTED);
            }
        }
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

    // A transient endpoint failure after NetworkManager came online should
    // not survive until the ordinary (30 minute by default) poll. Four
    // bounded retries cover startup DNS/repository lag without hammering a
    // permanently broken remote.
    Timer {
        interval: Math.min(120000, 15000 * Math.pow(2,
            Math.max(0, root.checkFailureCount - 1)))
        running: root.error !== "" && root.checkFailureCount <= 4
            && NetworkStatus.online && !root.busy && !root.runActive
        onTriggered: root.automaticCheck(false)
    }

    Timer {
        interval: Math.max(10, Settings.modOpts.updates.pollMins) * 60000
        running: NetworkStatus.online
        repeat: true
        onTriggered: root.automaticCheck(true)
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

    Connections {
        target: NetworkStatus

        function onOnlineChanged() {
            if (NetworkStatus.online)
                root.automaticCheck(true);
        }
    }

    Component.onCompleted: {
        initialized = true;
        automaticCheck(true);
    }
    onFlatpakEnabledChanged: {
        if (initialized)
            automaticCheck(true);
    }
}
