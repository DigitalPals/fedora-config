#!/usr/bin/env python3
"""User-owned widget packages and preferences; no release-tree writes."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import tempfile


API_VERSION = 1
ID = re.compile(r"[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*\Z")


def roots() -> tuple[Path, Path, Path]:
    home = Path.home()
    config = Path(os.environ.get("FEDORA_CONFIG_USER_CONFIG_ROOT") or
                  Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config") / "fedora-config")
    packages = Path(os.environ.get("FEDORA_CONFIG_PLUGIN_ROOT") or
                    Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share") /
                    "fedora-config/plugins")
    # Persistent plugin data is not disposable updater/diagnostic state. The
    # uninstaller may remove the latter while retaining user customizations.
    state = Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share") / "fedora-config/plugin-data"
    return config / "plugins.json", packages, state


def read_object(path: Path) -> dict:
    if path.stat().st_size > 1024 * 1024:
        raise ValueError(f"{path.name} exceeds 1 MiB")
    value = json.loads(path.read_text(encoding="utf-8"))
    json.dumps(value, allow_nan=False)
    if not isinstance(value, dict):
        raise ValueError(f"{path.name} must contain a JSON object")
    return value


def preferences(path: Path) -> dict:
    try:
        value = read_object(path)
    except FileNotFoundError:
        return {"v": 1, "plugins": {}}
    if type(value.get("v")) is not int or value["v"] != 1:
        raise ValueError("Unsupported plugins.json version; preferences were preserved")
    if not isinstance(value.get("plugins"), dict):
        raise ValueError("plugins.json must have a plugins object")
    return value


def package(packages: Path, plugin_id: str) -> dict:
    if not ID.fullmatch(plugin_id):
        raise ValueError("Invalid plugin id (use lowercase letters, digits, dots or hyphens)")
    directory = packages / plugin_id
    manifest = read_object(directory / "manifest.json")
    if manifest.get("id") != plugin_id:
        raise ValueError("Manifest id must match its directory name")
    if type(manifest.get("apiVersion")) is not int or manifest["apiVersion"] != API_VERSION:
        raise ValueError(f"Unsupported widget API {manifest.get('apiVersion')}; host supports 1")
    for key in ("name", "version", "entrypoint"):
        if not isinstance(manifest.get(key), str) or not manifest[key].strip():
            raise ValueError(f"Manifest needs a nonempty {key}")
    entry = Path(manifest["entrypoint"])
    if entry.is_absolute() or ".." in entry.parts or entry.suffix != ".qml":
        raise ValueError("Entrypoint must be a relative .qml path inside the package")
    source = (directory / entry).resolve()
    if not source.is_relative_to(directory.resolve()) or not source.is_file():
        raise ValueError("Entrypoint is missing or resolves outside the package")
    return {"id": plugin_id, "name": manifest["name"], "version": manifest["version"],
            "source": source.as_uri(), "packagePath": str(directory.resolve())}


def options(value: object) -> dict:
    if not isinstance(value, dict):
        raise ValueError("Plugin preferences must be an object")
    enabled = value.get("enabled", False)
    width = value.get("width", 120)
    order = value.get("order", 0)
    settings = value.get("settings", {})
    if type(enabled) is not bool:
        raise ValueError("enabled must be a boolean")
    if type(width) is not int or not 24 <= width <= 320:
        raise ValueError("width must be an integer from 24 to 320")
    if type(order) is not int:
        raise ValueError("order must be an integer")
    if not isinstance(settings, dict):
        raise ValueError("settings must be an object")
    return {"enabled": enabled, "width": width, "order": order, "settings": settings}


def scan(config: Path, packages: Path, state: Path) -> dict:
    try:
        saved = preferences(config)["plugins"]
    except (OSError, ValueError) as error:
        return {"apiVersion": API_VERSION, "error": str(error), "plugins": []}
    found = set(saved)
    try:
        found.update(path.name for path in packages.iterdir()
                     if path.is_dir() and not path.name.startswith("."))
    except FileNotFoundError:
        pass
    result = []
    for plugin_id in sorted(found):
        descriptor = {"id": plugin_id, "name": plugin_id, "enabled": False,
                      "order": 0, "width": 120, "settings": {}, "error": ""}
        try:
            descriptor.update(options(saved.get(plugin_id, {})))
            descriptor.update(package(packages, plugin_id))
            descriptor["dataPath"] = str(state / plugin_id)
        except (OSError, ValueError) as error:
            descriptor["error"] = str(error)
        result.append(descriptor)
    return {"apiVersion": API_VERSION, "error": "",
            "plugins": sorted(result, key=lambda item: (item["order"], item["id"]))}


@contextmanager
def locked(config: Path):
    config.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW
    with os.fdopen(os.open(str(config) + ".lock", flags, 0o600), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if config.is_symlink():
            raise ValueError("Refusing to replace a symlinked plugins.json")
        yield


def write_preferences(config: Path, value: dict) -> None:
    # Preserve unknown fields, even when written by a newer compatible host.
    encoded = json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    if len(encoded.encode("utf-8")) > 1024 * 1024:
        raise ValueError("plugins.json would exceed 1 MiB; store large data in the plugin data directory")
    descriptor, temporary = tempfile.mkstemp(prefix=".plugins-", dir=config.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, config)
        directory = os.open(config.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("list", help="Inspect installed widgets and compatibility as JSON")
    enable = commands.add_parser("enable", help="Enable a trusted local widget")
    enable.add_argument("id")
    enable.add_argument("--width", type=int)
    enable.add_argument("--order", type=int)
    disable = commands.add_parser("disable", help="Disable a widget, retaining its files and settings")
    disable.add_argument("id")
    setting = commands.add_parser("set", help="Set one widget setting to a JSON value")
    setting.add_argument("id")
    setting.add_argument("key")
    setting.add_argument("value")
    args = parser.parse_args()
    config, packages, state = roots()
    try:
        if args.command == "list":
            print(json.dumps(scan(config, packages, state), ensure_ascii=False))
            return 0
        if not ID.fullmatch(args.id):
            raise ValueError("Invalid plugin id")
        with locked(config):
            value = preferences(config)
            entry = value["plugins"].setdefault(args.id, {})
            if not isinstance(entry, dict):
                raise ValueError("Plugin preferences must be an object")
            if args.command == "enable":
                package(packages, args.id)
                entry["enabled"] = True
                for key in ("width", "order"):
                    if getattr(args, key) is not None:
                        entry[key] = getattr(args, key)
                options(entry)
                (state / args.id).mkdir(parents=True, exist_ok=True)
            elif args.command == "disable":
                entry["enabled"] = False
            else:
                settings = entry.setdefault("settings", {})
                if not isinstance(settings, dict):
                    raise ValueError("Plugin settings must be an object")
                settings[args.key] = json.loads(args.value)
                options(entry)
            write_preferences(config, value)
        return 0
    except (OSError, ValueError) as error:
        parser.exit(2, f"user-plugins: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
