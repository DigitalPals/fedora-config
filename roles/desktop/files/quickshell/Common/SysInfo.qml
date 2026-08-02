pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

Singleton {
    id: root

    property int cpuTemp: 0
    property string uptime: ""
    property string kernel: ""
    readonly property string user: Quickshell.env("USER") || "user"
    property string host: "linux"

    // Shared idle-inhibit state (bar module + control center toggle).
    property bool idleInhibited: true
    property string tempPath: ""

    // Hypridle honors systemd's idle inhibitors directly. Keep this process
    // alive while the toggle is enabled because the Wayland inhibitor tied to
    // the bar layer surface is not consistently observed by Hypridle.
    Process {
        command: ["systemd-inhibit", "--what=idle", "--who=Quickshell",
            "--why=Idle inhibit enabled from the menubar", "--mode=block",
            "sleep", "infinity"]
        running: root.idleInhibited
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

    function readTemperature() {
        if (tempPath === "")
            return;
        const value = parseInt(tempView.text().trim());
        if (!isNaN(value))
            cpuTemp = Math.round(value / 1000);
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

    function refreshTailscale() {
        tsProc.running = false;
        tsProc.running = true;
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
            if (root.wifiDevice)
                bitrateProc.running = true;
        }
    }
}
