pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "Common" as Common
import "Settings" as SettingsUi

// tests/run overlays this file on an isolated copy of the production config
// before launching the real `qs` engine (never beside an existing live qs).
// Keeping dependencies inside the selected config root matches production and
// avoids Quickshell's intentional qrc:/qs-blackhole for out-of-root modules.
ShellRoot {
    id: root

    property bool failed: false
    property int toggles: 0
    property int actions: 0
    property Common.Revealer revealer: null
    property Common.Toggle toggle: null
    property SettingsUi.SettingsAction action: null
    property Common.StatusPlaceholder status: null

    function check(condition, message) {
        if (condition)
            return;
        failed = true;
        console.error("LIFECYCLE_FAIL " + message);
    }

    function runLifecycle() {
        root.revealer = revealerComponent.createObject(harness, { reveal: false });
        root.toggle = toggleComponent.createObject(harness);
        root.action = actionComponent.createObject(harness);
        root.status = statusComponent.createObject(harness,
            { kind: "loading", shown: true });
        root.check(root.revealer !== null, "Revealer did not construct");
        root.check(root.toggle !== null, "Toggle did not construct");
        root.check(root.action !== null, "SettingsAction did not construct");
        root.check(root.status !== null, "StatusPlaceholder did not construct");
        if (!root.failed) {
            root.check(root.revealer.implicitHeight === 0,
                "closed Revealer has non-zero height");
            root.toggle.toggled.connect(value => root.toggles += value ? 1 : 10);
            root.action.triggered.connect(() => root.actions++);
            root.revealer.reveal = true;
            root.toggle.toggled(true);
            root.action.triggered();
            root.status.kind = "error";
            root.check(root.revealer.implicitHeight === 28,
                "open Revealer did not adopt child height");
            root.check(root.toggles === 1, "Toggle signal was not delivered once");
            root.check(root.actions === 1, "Action signal was not delivered once");
            root.check(root.status.kind === "error", "Status state did not update");
            root.revealer.destroy();
            root.toggle.destroy();
            root.action.destroy();
            root.status.destroy();
        }
        // Warnings are mirrored to stderr by qs even without detailed-log
        // decoding, which makes the result observable to the shell driver.
        console.warn(root.failed ? "LIFECYCLE_RESULT fail" : "LIFECYCLE_RESULT pass");
        // A minimal ShellRoot has no production IPC object through which the
        // test driver can request shutdown. Terminate this exact test PID
        // after logging; timeout remains the outer leak guard.
        Quickshell.execDetached(["/usr/bin/bash", "-c",
            "sleep 0.2; kill -TERM -- \"$1\"", "bash", String(Quickshell.processId)]);
    }

    Component {
        id: revealerComponent
        Common.Revealer {
            Rectangle { width: 96; height: 28 }
        }
    }
    Component {
        id: toggleComponent
        Common.Toggle { accessibleName: "Lifecycle switch" }
    }
    Component {
        id: actionComponent
        SettingsUi.SettingsAction { text: "Refresh"; glyph: "refresh" }
    }
    Component {
        id: statusComponent
        Common.StatusPlaceholder {
            width: 360
            title: "Nothing here"
            detail: "A stable empty state"
        }
    }

    Item {
        id: harness
        width: 640
        height: 480
    }

    Component.onCompleted: runLifecycle()
}
