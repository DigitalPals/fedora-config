pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

Singleton {
    id: root

    property int cpuTemp: 0
    property real cpuUsage: 0 // percent
    property real memUsage: 0 // percent
    property int brightness: -1 // percent, -1 while unknown
    property string uptime: ""
    property string kernel: ""
    readonly property string user: Quickshell.env("USER") || "user"
    property string host: "linux"

    // Shared idle-inhibit state (bar module + control center toggle).
    property bool idleInhibited: true

    // Night light: hyprsunset warms the screen while enabled and restores
    // neutral gamma when the process is killed.
    property bool nightLight: false
    property string tempPath: ""
    property var cpuPrev: null

    // Hypridle honors systemd's idle inhibitors directly. Keep this process
    // alive while the toggle is enabled because the Wayland inhibitor tied to
    // the bar layer surface is not consistently observed by Hypridle.
    Process {
        command: ["systemd-inhibit", "--what=idle", "--who=Quickshell",
            "--why=Idle inhibit enabled from the menubar", "--mode=block",
            "sleep", "infinity"]
        running: root.idleInhibited
    }

    Process {
        id: sunsetProc
        command: ["hyprsunset", "--temperature", String(Settings.warmth)]
        running: root.nightLight
    }

    // Command changes are inert on a running process, so a warmth change
    // restarts it — debounced so a slider drag doesn't churn processes.
    Timer {
        id: warmthRestart
        interval: 300
        onTriggered: {
            if (root.nightLight) {
                sunsetProc.running = false;
                sunsetProc.running = true;
            }
        }
    }

    Connections {
        target: Settings

        function onWarmthChanged() {
            warmthRestart.restart();
        }
    }

    // Tailscale status
    property bool tsRunning: false
    property string tsHost: ""
    property string tsNet: ""
    property string tsIp: ""
    property bool tsExitNode: false

    // Wi-Fi link speed, e.g. "1152 Mb/s"
    property string wifiBitrate: ""
    readonly property var wifiDevice: Networking.devices.values.find(device => device.networks !== undefined) ?? null

    Process {
        command: ["cat", "/etc/hostname"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.host = text.trim()
        }
    }

    Process {
        command: ["uname", "-r"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.kernel = text.trim()
        }
    }

    // Discover the CPU sensor once, then use cheap FileView reloads.
    Process {
        id: sensorDiscovery
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do [ \"$(cat \"$h/name\" 2>/dev/null)\" = coretemp ] && { printf '%s' \"$h/temp1_input\"; exit; }; done"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.tempPath = text.trim()
        }
    }

    FileView {
        id: tempView
        path: root.tempPath
        printErrors: false
        onLoaded: root.readTemperature()
    }

    FileView {
        id: uptimeView
        path: "/proc/uptime"
        onLoaded: root.readUptime()
    }

    FileView {
        id: statView
        path: "/proc/stat"
        onLoaded: root.readCpu()
    }

    FileView {
        id: memView
        path: "/proc/meminfo"
        onLoaded: root.readMem()
    }

    function readTemperature() {
        if (tempPath === "")
            return;
        const value = parseInt(tempView.text().trim());
        if (!isNaN(value))
            cpuTemp = Math.round(value / 1000);
    }

    function readCpu() {
        const fields = statView.text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
        if (fields.length < 5 || fields.some(isNaN))
            return;
        const total = fields.reduce((a, b) => a + b, 0);
        const idle = fields[3] + (fields[4] || 0);
        if (cpuPrev !== null) {
            const dTotal = total - cpuPrev.total;
            if (dTotal > 0)
                cpuUsage = Math.max(0, Math.min(100, (dTotal - (idle - cpuPrev.idle)) / dTotal * 100));
        }
        cpuPrev = { total: total, idle: idle };
    }

    function readMem() {
        const text = memView.text();
        const total = parseInt((text.match(/MemTotal:\s+(\d+)/) || [])[1]);
        const avail = parseInt((text.match(/MemAvailable:\s+(\d+)/) || [])[1]);
        if (total > 0 && !isNaN(avail))
            memUsage = Math.max(0, Math.min(100, (total - avail) / total * 100));
    }

    function setBrightness(pct) {
        pct = Math.max(1, Math.min(100, Math.round(pct)));
        brightness = pct;
        Quickshell.execDetached(["brightnessctl", "set", pct + "%"]);
    }

    function readUptime() {
        const secs = parseFloat(uptimeView.text().split(" ")[0]);
        if (isNaN(secs))
            return;
        const d = Math.floor(secs / 86400);
        const h = Math.floor((secs % 86400) / 3600);
        const m = Math.floor((secs % 3600) / 60);
        uptime = d > 0 ? `${d} d ${h} h` : (h > 0 ? `${h} h ${m} m` : `${m} m`);
    }

    onTempPathChanged: {
        if (tempPath !== "") {
            tempView.reload();
            readTemperature();
        }
    }

    Process {
        id: tsProc
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(text);
                    root.tsRunning = s.BackendState === "Running";
                    root.tsHost = s.Self && s.Self.HostName || "";
                    root.tsNet = s.MagicDNSSuffix || "";
                    root.tsIp = s.Self && s.Self.TailscaleIPs && s.Self.TailscaleIPs[0] || "";
                    root.tsExitNode = !!(s.ExitNodeStatus && s.ExitNodeStatus.Online);
                } catch (e) {
                    root.tsRunning = false;
                }
            }
        }
    }

    Process {
        id: bitrateProc
        command: root.wifiDevice ? ["iw", "dev", root.wifiDevice.name, "link"] : []
        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/tx bitrate:\s*([0-9.]+)/);
                const v = match ? parseFloat(match[1]) : NaN;
                root.wifiBitrate = isNaN(v) ? "" : Math.round(v) + " Mb/s";
            }
        }
    }

    Process {
        id: brightnessProc
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const pct = parseInt((text.trim().split(",")[3] || "").replace("%", ""));
                if (!isNaN(pct))
                    root.brightness = pct;
            }
        }
    }

    function refreshTailscale() {
        tsProc.running = false;
        tsProc.running = true;
    }

    function refreshBrightness() {
        brightnessProc.running = false;
        brightnessProc.running = true;
    }

    // CPU / RAM sampling for the Control Center stat cards.
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statView.reload();
            root.readCpu();
            memView.reload();
            root.readMem();
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root.tempPath !== "") {
                tempView.reload();
                root.readTemperature();
            }
        }
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            uptimeView.reload();
            root.readUptime();
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            tsProc.running = true;
            brightnessProc.running = true;
            if (root.wifiDevice)
                bitrateProc.running = true;
        }
    }
}
