import QtQuick
import Quickshell
import "Common"
import "Bar"

ShellRoot {
    id: root
    property int attempts: 0
    property bool finished: false
    property bool saved: false
    property var hosts: []

    function done(ok, detail) {
        if (finished)
            return;
        finished = true;
        console.warn("USER_WIDGET_RESULT " + (ok ? "pass " : "fail ") + detail);
        Quickshell.execDetached(["/usr/bin/bash", "-c",
            "sleep 0.2; kill -TERM -- \"$1\"", "bash", String(Quickshell.processId)]);
    }

    Component {
        id: factory
        UserWidgetHost {
            width: 120
            height: 30
            screenName: "test-output"
            themeValues: ({ foreground: "#ffffff", background: "#000000", accent: "#00ff00",
                fontFamily: "sans-serif", fontSize: 13, reducedMotion: true })
            onSettingRequested: (pluginId, key, value) => UserPlugins.setSetting(pluginId, key, value)
        }
    }
    Item {
        id: canvas
        width: 640
        height: 480
        UserWidgets {
            id: barWidgets
            screenName: "test-output"
            availableWidth: 320
        }
    }
    Timer {
        interval: 100
        repeat: true
        running: !root.finished
        onTriggered: {
            if (++root.attempts > 90) {
                root.done(false, "timeout: " + UserPlugins.error + " " + root.hosts.map(h => h.error));
                return;
            }
            if (UserPlugins.plugins.length !== 3)
                return;
            if (root.hosts.length === 0) {
                for (const descriptor of UserPlugins.plugins) {
                    const host = factory.createObject(canvas, { descriptor: descriptor });
                    if (!host) {
                        root.done(false, "host construction failed");
                        return;
                    }
                    root.hosts.push(host);
                }
            }
            const good = root.hosts.find(h => h.descriptor.id === "example.good");
            const bad = root.hosts.find(h => h.descriptor.id === "example.broken");
            const future = root.hosts.find(h => h.descriptor.id === "example.future");
            if (!good.ready || !bad.error || !future.error)
                return;
            if (bad.ready || future.ready || !good.widget.apiContract
                    || good.widget.text !== "preserved:1:test-output") {
                root.done(false, "API or isolation contract failed");
                return;
            }
            if (Quickshell.env("WIDGET_TEST_WRITE") === "1" && !root.saved) {
                good.widget.pluginApi.setSetting("savedByWidget", true);
                root.saved = true;
                return;
            }
            if (root.saved && !UserPlugins.plugins.find(p => p.id === "example.good").settings.savedByWidget)
                return;
            if (barWidgets.implicitWidth > 320 || barWidgets.hiddenWidgets.length === 0) {
                root.done(false, "widget display budget failed");
                return;
            }
            for (const host of root.hosts)
                host.destroy();
            root.done(true, "external package loaded; invalid widgets isolated; API survived");
        }
    }
}
