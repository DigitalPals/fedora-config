pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int cpuTemp: 0
    property string uptime: ""
    property string kernel: ""
    readonly property string user: Quickshell.env("USER") || "user"
    property string host: "linux"

    // Shared idle-inhibit state (bar module + control center toggle).
    property bool idleInhibited: false

    // Tailscale status
    property bool tsRunning: false
    property string tsHost: ""
    property string tsNet: ""
    property string tsIp: ""
    property bool tsExitNode: false

    // Wi-Fi link speed, e.g. "1152 Mb/s"
    property string wifiBitrate: ""

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

    Process {
        id: tempProc
        command: ["bash", "-c", "for h in /sys/class/hwmon/hwmon*; do if [ \"$(cat $h/name 2>/dev/null)\" = coretemp ]; then cat $h/temp1_input; exit 0; fi; done; echo 0"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseInt(text.trim());
                if (!isNaN(v))
                    root.cpuTemp = Math.round(v / 1000);
            }
        }
    }

    Process {
        id: uptimeProc
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const secs = parseFloat(text.split(" ")[0]);
                if (isNaN(secs))
                    return;
                const d = Math.floor(secs / 86400);
                const h = Math.floor((secs % 86400) / 3600);
                const m = Math.floor((secs % 3600) / 60);
                root.uptime = d > 0 ? `${d} d ${h} h` : (h > 0 ? `${h} h ${m} m` : `${m} m`);
            }
        }
    }

    Process {
        id: tsProc
        command: ["bash", "-c", "tailscale status --json 2>/dev/null | jq -c '{state:.BackendState,host:.Self.HostName,net:.MagicDNSSuffix,ip:.Self.TailscaleIPs[0],exit:(.ExitNodeStatus.Online // false)}' || echo '{}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(text);
                    root.tsRunning = s.state === "Running";
                    root.tsHost = s.host || "";
                    root.tsNet = s.net || "";
                    root.tsIp = s.ip || "";
                    root.tsExitNode = !!s.exit;
                } catch (e) {}
            }
        }
    }

    Process {
        id: bitrateProc
        command: ["bash", "-c", "wl=$(ls /sys/class/net | grep -m1 '^wl'); [ -n \"$wl\" ] && iw dev \"$wl\" link 2>/dev/null | grep -oP 'tx bitrate: \\K[0-9.]+' | head -1 || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseFloat(text.trim());
                root.wifiBitrate = isNaN(v) ? "" : Math.round(v) + " Mb/s";
            }
        }
    }

    function refreshTailscale() {
        tsProc.running = false;
        tsProc.running = true;
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            tempProc.running = true;
            uptimeProc.running = true;
        }
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            tsProc.running = true;
            bitrateProc.running = true;
        }
    }
}
