pragma ComponentBehavior: Bound
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "ProcHelpers.js" as ProcHelpers
import "Format.js" as Format

Singleton {
    id: root

    readonly property var providerKeys: ["claude", "codex", "kimi"]
    readonly property var meta: ({
            claude: { name: "Claude", title: "Claude Code", brand: Theme.brandClaude, icon: "claude", cmd: "claude /login" },
            codex: { name: "Codex", title: "Codex CLI", brand: Theme.brandCodex, icon: "openai", cmd: "codex login" },
            kimi: { name: "Kimi", title: "Kimi Code", brand: Theme.brandKimi, icon: "kimi", cmd: "kimi login" }
        })

    readonly property int pollIntervalSecs: Settings.pollMax

    // The Model usage chip is the only thing that needs fresh figures without
    // being asked; with it off the bar, polling `usage-fetch.py` every few
    // minutes is pure idle churn. Settings.mods is replaced wholesale on every
    // edit, so this re-evaluates whenever the module list changes.
    readonly property bool pollEnabled: {
        const mods = Settings.mods;
        for (const col of ["left", "center", "right"]) {
            const hit = mods[col].find(m => m.id === "usage");
            if (hit)
                return hit.on;
        }
        return false;
    }

    Connections {
        target: Settings

        function onPollMaxChanged() {
            root.refresh();
        }
    }
    property var data: ({})
    property bool loading: true
    // Why the last `usage-fetch.py` run produced nothing usable, "" when it
    // worked. Distinct from a provider's own {"status": "error"} row — this
    // is the fetcher itself failing, so no provider figure is trustworthy.
    // Stays "" while the module is off: nothing is being fetched, and that
    // is not a failure.
    property string fetchError: ""
    property double updatedAt: 0
    // Seconds until the next scheduled fetch, derived from when the current
    // poll period started rather than counted down. A counter is only right
    // while something ticks it, which is why the popover used to resync on
    // open and the settings page recomputed its own copy; both now read this.
    // Anchored on the period, not on updatedAt: the timer fires on schedule
    // whether or not the fetch it started succeeded.
    property double pollStartedAt: 0
    property double countdownNow: 0
    readonly property int nextPollSecs: {
        if (!pollEnabled || pollStartedAt <= 0 || countdownNow <= 0)
            return pollIntervalSecs;
        const elapsed = Math.floor((countdownNow - pollStartedAt) / 1000);
        return Math.max(0, Math.min(pollIntervalSecs, pollIntervalSecs - elapsed));
    }

    // Only the views that show the countdown pay for a 1 Hz tick.
    property int countdownWatchers: 0

    function acquireCountdown() {
        countdownWatchers++;
        countdownNow = Date.now();
    }

    function releaseCountdown() {
        countdownWatchers = Math.max(0, countdownWatchers - 1);
    }
    property string selected: "claude"

    // Session-window usage sampled at every poll, per provider, kept for
    // seven days: { claude: [[ms, usedPct], …], … }. Backs the USAGE
    // HISTORY chart (design 1c) and persists across shell restarts.
    property var history: ({ claude: [], codex: [], kimi: [] })

    // True once any provider ever returned ok data.
    readonly property bool anyOk: providerKeys.some(k => data[k] && data[k].status === "ok")

    function provider(key) {
        return data[key] ?? null;
    }

    // Minimum remaining percent across a provider's windows, or -1.
    function minRemaining(key) {
        const p = provider(key);
        if (!p || p.status !== "ok" || !p.windows || p.windows.length === 0)
            return -1;
        return Math.round(Math.min(...p.windows.map(w => 100 - w.used)));
    }

    // "ok" | "warn" | "crit" | "error" | "none"
    function chipStatus(key) {
        const p = provider(key);
        if (!p)
            return "none";
        if (p.status !== "ok")
            return "error";
        const rem = minRemaining(key);
        if (rem < 0)
            return "none";
        if (rem <= Settings.modOpts.usage.critAt)
            return "crit";
        if (rem <= Settings.modOpts.usage.warnAt)
            return "warn";
        return "ok";
    }

    // Start a fetch, replacing one already in flight.
    function start() {
        loading = true;
        fetchProc.staleRuns += fetchProc.running ? 1 : 0;
        fetchProc.running = false;
        fetchProc.running = true;
    }

    function refresh() {
        start();
        // A manual refresh from the popover still works with the module off;
        // it just must not leave the poll timer running behind its binding.
        if (pollEnabled) {
            pollStartedAt = Date.now();
            pollTimer.restart();
        }
    }

    function formatReset(resetsAt) {
        if (!resetsAt)
            return "";
        let s = resetsAt - Date.now() / 1000;
        if (s <= 0)
            return "now";
        const d = Math.floor(s / Format.DAY);
        const h = Math.floor((s % Format.DAY) / Format.HOUR);
        const m = Math.floor((s % Format.HOUR) / Format.MINUTE);
        if (d > 0)
            return `${d}d ${Format.pad2(h)}h`;
        if (h > 0)
            return `${h}h ${m}m`;
        return `${Math.max(1, m)}m`;
    }

    // Absolute reset moment: "14:12" within 24h, else "Aug 5, 08:00".
    function formatResetAbs(resetsAt) {
        if (!resetsAt)
            return "";
        const d = new Date(resetsAt * 1000);
        if (resetsAt - Date.now() / 1000 < 86400)
            return Qt.formatTime(d, "HH:mm");
        return Qt.formatDateTime(d, "MMM d, HH:mm");
    }

    // ---- usage history ------------------------------------------------

    // Used % of the most dynamic window (the session window when present).
    function sessionUsed(p) {
        if (!p || p.status !== "ok" || !p.windows || p.windows.length === 0)
            return -1;
        const w = p.windows.find(w => /5.hour|session/i.test(w.label)) ?? p.windows[0];
        return Math.min(100, Math.max(0, w.used));
    }

    function recordSamples() {
        const now = Date.now();
        const cutoff = now - 7 * 86400 * 1000;
        const next = {};
        for (const k of providerKeys) {
            const arr = (history[k] ?? []).filter(s => s[0] >= cutoff);
            const used = sessionUsed(provider(k));
            if (used >= 0)
                arr.push([now, Math.round(used)]);
            next[k] = arr;
        }
        history = next;
        // FileView.adapter has an incomplete type in the qmltypes, so qmllint
        // cannot see ids declared under it. The id resolves normally at
        // runtime — verified against a live instance under this pragma.
        // qmllint disable unqualified
        histData.claude = next.claude;
        histData.codex = next.codex;
        histData.kimi = next.kimi;
        // qmllint enable unqualified
        histFile.writeAdapter();
    }

    // Bucketed chart values (0..100): 24 hourly buckets or 7 daily ones.
    // Empty buckets carry the last known level so the chart reads as a
    // continuous line even with sparse samples.
    function histBars(key, mode) {
        const samples = history[key] ?? [];
        const buckets = mode === "d7" ? 7 : 24;
        const span = (mode === "d7" ? 7 * 86400 : 24 * 3600) * 1000;
        const start = Date.now() - span;
        const out = new Array(buckets).fill(-1);
        for (const s of samples) {
            if (s[0] < start)
                continue;
            const i = Math.min(buckets - 1, Math.floor((s[0] - start) / (span / buckets)));
            out[i] = Math.max(out[i], s[1]);
        }
        let last = 0;
        for (let i = 0; i < buckets; i++) {
            if (out[i] < 0)
                out[i] = last;
            else
                last = out[i];
        }
        return out;
    }

    FileView {
        id: histFile
        path: Quickshell.env("HOME") + "/.local/state/quickshell-usage-history.json"
        printErrors: false
        // qmllint disable unqualified
        onLoaded: root.history = {
            claude: histData.claude ?? [],
            codex: histData.codex ?? [],
            kimi: histData.kimi ?? []
        }
        // qmllint enable unqualified

        JsonAdapter {
            id: histData
            property var claude: []
            property var codex: []
            property var kimi: []
        }
    }

    // Everything a finished run has to say, in one place. `loading` clears
    // here whatever happened, including the case where python3 itself could
    // not be launched (ProcHelpers.NOT_STARTED) and no output ever arrived.
    function settle(exitCode, body, errText) {
        loading = false;
        if (exitCode !== 0) {
            fetchError = ProcHelpers.commandError("usage-fetch.py", exitCode, errText);
            console.warn("usage-fetch failed:", fetchError);
            return;
        }
        let parsed = null;
        try {
            parsed = JSON.parse(body);
        } catch (e) {
            console.warn("usage-fetch parse failed:", e);
        }
        if (!parsed || typeof parsed !== "object") {
            fetchError = "usage-fetch.py returned output this shell could not read";
            return;
        }
        // Deliberately outside the try: a throw out of recordSamples() should
        // reach the journal as itself, not pose as unreadable output.
        data = parsed;
        updatedAt = Date.now();
        recordSamples();
        fetchError = "";
    }

    Process {
        id: fetchProc
        // The script prints JSON and exits 0 even when a provider is signed
        // out — a nonzero status or a silent start failure means the fetcher
        // itself broke, and its traceback is on stderr. Both streams close
        // before exited(), and the falling edge of `running` is the only
        // signal that arrives when the binary cannot be launched at all.
        //
        // Runs killed by start() have yet to report in: their exit lands as a
        // crash some time after the replacement started, and is not news.
        property int staleRuns: 0
        property string body: ""
        property string errText: ""
        property bool exitSeen: false
        property int lastExit: 0

        command: ["python3", Quickshell.shellDir + "/scripts/usage-fetch.py"]

        stdout: StdioCollector {
            onStreamFinished: fetchProc.body = text
        }
        stderr: StdioCollector {
            onStreamFinished: fetchProc.errText = text
        }
        onExited: (exitCode, exitStatus) => {
            fetchProc.exitSeen = true;
            fetchProc.lastExit = exitCode;
        }
        onRunningChanged: {
            if (running) {
                body = "";
                errText = "";
                exitSeen = false;
                lastExit = 0;
            } else if (staleRuns > 0) {
                staleRuns--;
            } else {
                root.settle(exitSeen ? lastExit : ProcHelpers.NOT_STARTED, body, errText);
            }
        }
    }

    Timer {
        id: pollTimer
        interval: root.pollIntervalSecs * 1000
        running: root.pollEnabled
        repeat: true
        // Switching the module back on starts a fresh period.
        onRunningChanged: {
            if (running)
                root.pollStartedAt = Date.now();
        }
        onTriggered: {
            root.pollStartedAt = Date.now();
            root.start();
        }
    }

    // Warm-up: shell.qml touches this singleton at session start so the chip
    // has figures before the first interval elapses, and the same fetch primes
    // it when the module is switched back on from the settings panel. With the
    // module off there is nothing to load and nothing left loading.
    function warmUp() {
        if (!pollEnabled) {
            loading = false;
            fetchError = "";
            return;
        }
        if (fetchProc.running)
            return;
        loading = true;
        fetchProc.running = true;
    }

    Timer {
        interval: 1000
        running: root.countdownWatchers > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.countdownNow = Date.now()
    }

    onPollEnabledChanged: warmUp()

    Component.onCompleted: warmUp()
}
