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
    readonly property bool idleInhibited: Settings.idleInhibited

    // Night light: hyprsunset warms the screen while enabled and restores
    // neutral gamma when the process is killed.
    readonly property bool nightLight: Settings.nightLight
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

    function setNightLight(value) {
        Settings.set("nightLight", !!value);
    }

    function toggleNightLight() {
        setNightLight(!nightLight);
    }

    function setIdleInhibited(value) {
        Settings.set("idleInhibited", !!value);
    }

    function toggleIdleInhibited() {
        setIdleInhibited(!idleInhibited);
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

    // ---- brightness --------------------------------------------------
    // Both directions go through brightness-control, because which screen is
    // in front of you decides whether brightness is a sysfs backlight or an
    // Apple display speaking USB HID, and that is not this singleton's
    // business to know. Reading used to be a direct sysfs read — free, and
    // the right number only while the laptop panel was the display. Docked to
    // the Studio Display it reported the closed lid's backlight, and writing
    // brightnessctl moved that panel instead of the one being looked at.
    readonly property string brightnessTool:
        Quickshell.env("HOME") + "/.local/bin/brightness-control"

    // The reading follows the pointer immediately so the slider stays live
    // under a drag; the process that writes it is coalesced onto the last
    // value, since a drag emits one on every mouse move.
    property int pendingBrightness: -1

    function setBrightness(pct) {
        pct = Math.max(0, Math.min(100, Math.round(pct)));
        brightness = pct;
        pendingBrightness = pct;
        brightnessWrite.restart();
    }

    Timer {
        id: brightnessWrite
        interval: 60
        onTriggered: {
            if (root.pendingBrightness < 0)
                return;
            // A write still in flight owns the device; re-arm rather than
            // start a second one over the top of it.
            if (brightnessSet.running) {
                brightnessWrite.restart();
                return;
            }
            brightnessSet.command = [root.brightnessTool, "set",
                String(root.pendingBrightness)];
            root.pendingBrightness = -1;
            brightnessSet.running = true;
            brightnessSettle.restart();
        }
    }

    Process {
        id: brightnessSet
    }

    // A write that has not landed yet is still the truth: a read overtaking
    // it would drag the slider back to a value the pointer has already left.
    Timer {
        id: brightnessSettle
        interval: 400
    }

    // Nothing about either backend is watchable — sysfs backlight attributes
    // deliver no inotify events and a HID write emits none — so every
    // consumer that can observe an external change calls this. The OSD does,
    // over IPC from brightness-control itself.
    function refreshBrightness() {
        if (brightnessRead.running || brightnessWrite.running
                || brightnessSettle.running)
            return;
        brightnessRead.running = true;
    }

    Process {
        id: brightnessRead
        command: [root.brightnessTool, "get"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const value = parseInt(text.trim());
                if (!isNaN(value))
                    root.brightness = Math.max(0, Math.min(100, value));
            }
        }
    }

    onTempPathChanged: {
        if (tempPath !== "") {
            tempView.reload();
            readTemperature();
        }
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

    // CPU / RAM sampling for the Control Panel stat cards. Idle wakeups
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
    // read itself after every key press. The slow poll is only here to catch
    // a change this machine made no request for — a docked display swapped
    // under it, say. Tailscale moved to its own singleton, which polls on the
    // same watcher basis.
    Timer {
        interval: 30000
        running: root.watchers > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshBrightness()
    }

    Component.onCompleted: syncNightLight()
}
