pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int cpuTemp: 0
    property real cpuUsage: 0 // percent
    property real memUsage: 0 // percent
    property int brightness: -1 // percent, -1 while unknown
    readonly property string user: Quickshell.env("USER") || "user"
    property string host: "linux"

    // Shared idle-inhibit state (bar module + control center toggle).
    property bool idleInhibited: true

    // Night light: hyprsunset warms the screen while enabled and restores
    // neutral gamma when the process is killed.
    property bool nightLight: false
    property string nightLightLifecycle: "stopped"
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
        running: false

        onExited: {
            if (root.nightLightLifecycle === "restarting" && root.nightLight) {
                root.nightLightLifecycle = "starting";
                sunsetProc.command = ["hyprsunset", "--temperature", String(Settings.warmth)];
                sunsetProc.running = true;
                root.nightLightLifecycle = "running";
            } else {
                root.nightLightLifecycle = "stopped";
            }
        }
    }

    function syncNightLight() {
        if (nightLight) {
            if (sunsetProc.running)
                return;
            nightLightLifecycle = "starting";
            sunsetProc.command = ["hyprsunset", "--temperature", String(Settings.warmth)];
            sunsetProc.running = true;
            nightLightLifecycle = "running";
        } else if (sunsetProc.running) {
            nightLightLifecycle = "stopping";
            sunsetProc.running = false;
        } else {
            nightLightLifecycle = "stopped";
        }
    }

    onNightLightChanged: syncNightLight()

    // Command changes are inert on a running process, so a warmth change
    // restarts it — debounced so a slider drag doesn't churn processes.
    Timer {
        id: warmthRestart
        interval: 300
        onTriggered: {
            if (root.nightLight && sunsetProc.running) {
                root.nightLightLifecycle = "restarting";
                sunsetProc.running = false;
            } else if (root.nightLight)
                root.syncNightLight();
        }
    }

    Connections {
        target: Settings

        function onWarmthChanged() {
            warmthRestart.restart();
        }
    }

    Process {
        command: ["cat", "/etc/hostname"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.host = text.trim()
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

    onTempPathChanged: {
        if (tempPath !== "") {
            tempView.reload();
            readTemperature();
        }
    }

    // Backlight. Reading is a plain sysfs read — the OSD asks for a fresh
    // value on every brightness key press, and forking brightnessctl for
    // that is the most expensive thing on the hot path. Writing still goes
    // through brightnessctl: sysfs backlight writes need privileges that it
    // gets from systemd-logind.
    property string backlightPath: ""
    property int backlightMax: 0

    // Discover the backlight once, like the CPU sensor above.
    Process {
        id: backlightDiscovery
        command: ["sh", "-c", "for d in /sys/class/backlight/*; do [ -r \"$d/brightness\" ] && { printf '%s' \"$d\"; exit; }; done"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.backlightPath = text.trim()
        }
    }

    FileView {
        id: backlightMaxView
        path: root.backlightPath === "" ? "" : root.backlightPath + "/max_brightness"
        printErrors: false
        onLoaded: {
            const value = parseInt(backlightMaxView.text().trim());
            root.backlightMax = isNaN(value) || value <= 0 ? 0 : value;
            root.readBrightness();
        }
    }

    FileView {
        id: backlightView
        path: root.backlightPath === "" ? "" : root.backlightPath + "/brightness"
        printErrors: false
        onLoaded: root.readBrightness()
    }

    // brightnessctl reports a plain rounded ratio of brightness/max_brightness
    // (verified against `brightnessctl -m -p set N` across the range), so the
    // OSD, the control-centre slider and the CLI all agree.
    function readBrightness() {
        if (backlightMax <= 0)
            return;
        const value = parseInt(backlightView.text().trim());
        if (!isNaN(value))
            brightness = Math.max(0, Math.min(100, Math.round(value * 100 / backlightMax)));
    }

    onBacklightPathChanged: {
        if (backlightPath !== "") {
            backlightMaxView.reload();
            backlightView.reload();
        }
    }

    // Backlight sysfs attributes do not deliver inotify events, so there is
    // nothing to watch: every consumer that can observe an external change
    // (the OSD, over IPC from brightness-control) calls this instead.
    function refreshBrightness() {
        if (backlightPath === "")
            return;
        backlightView.reload();
        readBrightness();
    }

    // ---- watchers ---------------------------------------------------
    // Which views are on screen is their business, not this singleton's:
    // it used to sample whenever *any* popout was open, so opening the
    // media panel read /proc/stat for nobody. A view that wants these
    // figures says so for as long as it is alive.
    property int watchers: 0

    function acquire() {
        watchers++;
    }

    function release() {
        watchers = Math.max(0, watchers - 1);
    }

    // CPU / RAM sampling for the Control Center stat cards. Idle wakeups
    // are not free on battery, and nothing else displays these values.
    // triggeredOnStart refreshes the cards the moment a watcher arrives.
    Timer {
        interval: 5000
        running: root.watchers > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statView.reload();
            root.readCpu();
            memView.reload();
            root.readMem();
        }
    }

    // Temperature has exactly one reader, the same stat card as CPU and
    // RAM, but used to poll for the whole session. Same watcher basis;
    // triggeredOnStart still fills the card on open.
    Timer {
        interval: 10000
        running: root.watchers > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root.tempPath !== "") {
                tempView.reload();
                root.readTemperature();
            }
        }
    }

    // Brightness is read by the control centre; the OSD asks for a fresh
    // read itself after every key press. Tailscale moved to its own
    // singleton, which polls on the same watcher basis.
    Timer {
        interval: 30000
        running: root.watchers > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshBrightness()
    }
}
