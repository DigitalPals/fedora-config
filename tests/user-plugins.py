#!/usr/bin/env python3
"""Exercise real external widgets through runtime replacement and rollback."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SHELL = ROOT / "roles/desktop/files/quickshell"
HELPER = SHELL / "scripts/user-plugins.py"


def run(*args, env, check=True):
    return subprocess.run([str(arg) for arg in args], env=env, text=True,
                          capture_output=True, check=check)


def main():
    with tempfile.TemporaryDirectory(prefix="fedora-config-user-widgets.") as temporary:
        base = Path(temporary)
        env = dict(os.environ, HOME=str(base / "home"),
                   XDG_CONFIG_HOME=str(base / "config"),
                   XDG_DATA_HOME=str(base / "data"), XDG_STATE_HOME=str(base / "state"),
                   XDG_RUNTIME_DIR=str(base / "run"), QT_QPA_PLATFORM="offscreen",
                   QT_QUICK_BACKEND="software")
        for key in ("FEDORA_CONFIG_USER_CONFIG_ROOT", "FEDORA_CONFIG_PLUGIN_ROOT"):
            env.pop(key, None)
        (base / "run").mkdir(mode=0o700)
        packages = base / "data/fedora-config/plugins"
        config = base / "config/fedora-config/plugins.json"
        for plugin_id, api in (("example.good", 1), ("example.broken", 1), ("example.future", 2)):
            directory = packages / plugin_id
            directory.mkdir(parents=True)
            (directory / "manifest.json").write_text(json.dumps({
                "id": plugin_id, "apiVersion": api, "name": plugin_id,
                "version": "1.0.0", "entrypoint": "Widget.qml"}))
            (directory / "Widget.qml").write_text("import QtQuick\nItem {}\n")
        good = packages / "example.good"
        # An external relative import must work too, not just a self-contained root.
        (good / "Label.qml").write_text("import QtQuick\nText {}\n")
        (good / "Widget.qml").write_text('''import QtQuick
Label {
    required property var pluginApi
    text: pluginApi.settings.label + ":" + pluginApi.version + ":" + pluginApi.screenName
    color: pluginApi.theme.foreground
    readonly property bool apiContract: pluginApi.id === "example.good"
        && pluginApi.version === 1 && pluginApi.width === width && pluginApi.height === height
        && pluginApi.dataPath.endsWith("plugin-data/example.good")
        && pluginApi.packagePath.endsWith("plugins/example.good")
        && typeof pluginApi.setSetting === "function"
        && typeof pluginApi.theme.foreground === "string"
        && typeof pluginApi.theme.background === "string"
        && typeof pluginApi.theme.accent === "string"
        && typeof pluginApi.theme.fontFamily === "string"
        && typeof pluginApi.theme.fontSize === "number"
        && typeof pluginApi.theme.reducedMotion === "boolean"
}
''')
        (packages / "example.broken/Widget.qml").write_text("import QtQuick\nBroken {{{\n")

        def cli(*args, check=True):
            return run("python3", HELPER, *args, env=env, check=check)

        assert all(not item["enabled"] for item in json.loads(cli("list").stdout)["plugins"])
        cli("enable", "example.good", "--width", "140", "--order", "2")
        cli("set", "example.good", "label", '"preserved"')
        cli("enable", "example.broken")
        assert cli("enable", "example.future", check=False).returncode == 2
        assert cli("enable", "../escape", check=False).returncode == 2
        saved = json.loads(config.read_text())
        saved["futureField"] = {"keep": True}
        saved["plugins"]["example.good"]["futureField"] = [1, 2]
        saved["plugins"]["example.future"] = {"enabled": True, "settings": {"keep": True}}
        config.write_text(json.dumps(saved))
        cli("disable", "example.good")
        cli("enable", "example.good")
        saved = json.loads(config.read_text())
        assert saved["futureField"] == {"keep": True}
        assert saved["plugins"]["example.good"]["futureField"] == [1, 2]
        assert saved["plugins"]["example.good"]["width"] == 140

        # Simultaneous writers merge under the lock instead of losing preferences.
        writers = [subprocess.Popen(["python3", str(HELPER), "set", "example.good",
                                     f"concurrent{index}", str(index)], env=env)
                   for index in range(8)]
        assert all(writer.wait() == 0 for writer in writers)
        saved = json.loads(config.read_text())
        assert all(saved["plugins"]["example.good"]["settings"][f"concurrent{i}"] == i
                   for i in range(8))

        # Corrupt and newer schemas are neither reset nor downgraded by a write.
        original = config.read_bytes()
        for invalid in (b"{corrupt", b'{"v":2,"plugins":{}}',
                        b'{"v":1,"plugins":{},"extra":NaN}'):
            config.write_bytes(invalid)
            assert cli("disable", "example.good", check=False).returncode == 2
            assert json.loads(cli("list").stdout)["error"]
            assert config.read_bytes() == invalid
        config.write_bytes(original)

        # Reject entrypoint traversal and symlink escapes without changing preferences.
        manifest = good / "manifest.json"
        original_manifest = manifest.read_bytes()
        for entrypoint in ("../example.broken/Widget.qml", str(good / "Widget.qml"), "Escape.qml"):
            candidate = json.loads(original_manifest)
            candidate["entrypoint"] = entrypoint
            manifest.write_text(json.dumps(candidate))
            if entrypoint == "Escape.qml":
                (good / entrypoint).symlink_to(packages / "example.broken/Widget.qml")
            assert cli("enable", "example.good", check=False).returncode == 2
            assert config.read_bytes() == original
        (good / "Escape.qml").unlink()
        manifest.write_bytes(original_manifest)

        if not shutil.which("qs"):
            raise RuntimeError("qs is required for user widget runtime tests")
        if any(path.read_text().strip() == "qs" for path in Path("/proc").glob("[0-9]*/comm")
               if path.exists()):
            print("User plugin storage tests passed; real-engine checks deferred to isolated CI (qs active)")
            return

        protected = {path: path.read_bytes() for path in packages.rglob("*") if path.is_file()}
        plugin_data = base / "data/fedora-config/plugin-data/example.good/history.json"
        plugin_data.write_text('{"userData":"preserved"}')
        protected[plugin_data] = plugin_data.read_bytes()
        protected[config] = config.read_bytes()
        runtime = base / "runtime"
        for release in ("N", "N+1", "rollback-N"):
            if runtime.exists():
                shutil.rmtree(runtime)
            shutil.copytree(SHELL, runtime)
            shutil.copy2(ROOT / "tests/user-widgets/shell.qml", runtime / "shell.qml")
            # A changed vendor file makes the replacement observable; packages
            # stay outside every runtime copy and expose only the frozen v1 API.
            (runtime / "release.txt").write_text(release)
            test_env = dict(env, WIDGET_TEST_WRITE="1" if release == "rollback-N" else "0")
            process = subprocess.Popen(["dbus-run-session", "--", "qs", "--no-color",
                                        "-p", str(runtime)], env=test_env,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, start_new_session=True)
            try:
                output, _ = process.communicate(timeout=14)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                output, _ = process.communicate(timeout=3)
                raise AssertionError(output) from None
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            assert "USER_WIDGET_RESULT pass" in output, output
            assert "USER_WIDGET_RESULT fail" not in output, output
            assert not re.search(r"(?:Type|Reference|Range)Error|Binding loop|Failed to load configuration", output), output
            for path, content in protected.items():
                if path != config or release != "rollback-N":
                    assert path.read_bytes() == content, f"{release} changed {path}"
            print(f"User widgets: {release} loaded external QML and preserved user packages")
        saved = json.loads(config.read_text())
        assert saved["plugins"]["example.good"]["settings"]["savedByWidget"] is True
        assert saved["futureField"] == {"keep": True}


if __name__ == "__main__":
    main()
