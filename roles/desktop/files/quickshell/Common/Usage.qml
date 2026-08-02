pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property var providerKeys: ["claude", "codex", "kimi"]
    readonly property var meta: ({
            claude: { name: "Claude", title: "Claude Code", brand: Theme.brandClaude, icon: "claude", cmd: "claude /login" },
            codex: { name: "Codex", title: "Codex CLI", brand: Theme.brandCodex, icon: "openai", cmd: "codex login" },
            kimi: { name: "Kimi", title: "Kimi Code", brand: Theme.brandKimi, icon: "kimi", cmd: "kimi login" }
        })

    readonly property int pollIntervalSecs: 300
    property var data: ({})
    property bool loading: true
    property double updatedAt: 0
    property int nextPollSecs: pollIntervalSecs
    property string selected: "claude"

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
        if (rem <= 10)
            return "crit";
        if (rem <= 25)
            return "warn";
        return "ok";
    }

    function refresh() {
        loading = true;
        fetchProc.running = false;
        fetchProc.running = true;
        nextPollSecs = pollIntervalSecs;
        pollTimer.restart();
    }

    function formatReset(resetsAt) {
        if (!resetsAt)
            return "";
        let s = resetsAt - Date.now() / 1000;
        if (s <= 0)
            return "now";
        const d = Math.floor(s / 86400);
        const h = Math.floor((s % 86400) / 3600);
        const m = Math.floor((s % 3600) / 60);
        if (d > 0)
            return `${d}d ${String(h).padStart(2, "0")}h`;
        if (h > 0)
            return `${h}h ${m}m`;
        return `${Math.max(1, m)}m`;
    }

    function formatCountdown(secs) {
        const m = Math.floor(secs / 60);
        const s = secs % 60;
        return `${m}:${String(s).padStart(2, "0")}`;
    }

    Process {
        id: fetchProc
        command: ["python3", Quickshell.shellDir + "/scripts/usage-fetch.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.data = JSON.parse(text);
                    root.updatedAt = Date.now();
                } catch (e) {
                    console.warn("usage-fetch parse failed:", e);
                }
                root.loading = false;
            }
        }
    }

    Timer {
        id: pollTimer
        interval: root.pollIntervalSecs * 1000
        running: true
        repeat: true
        onTriggered: {
            root.loading = true;
            fetchProc.running = false;
            fetchProc.running = true;
            root.nextPollSecs = root.pollIntervalSecs;
        }
    }

    Component.onCompleted: fetchProc.running = true
}
