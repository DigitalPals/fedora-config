#!/usr/bin/env python3
"""Focused contracts for immutable dependencies and tracked large assets."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SHA256 = re.compile(r"^sha256:[0-9a-f]{64}$")
SEMVER = re.compile(r"^[0-9]+[.][0-9]+[.][0-9]+(?:[.-][0-9A-Za-z.-]+)?$")


def executable(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/usr/bin/env bash\nset -eu\n" + body)
    path.chmod(0o755)


def render_user_updater(values: dict) -> str:
    updater = (ROOT / "roles/apps/templates/update-user-tools.j2").read_text()
    assert "{#" not in updater, "Bash syntax opened an unterminated Jinja comment"
    rendered = updater.replace(
        "{{ claude_code_version | quote }}", repr(values["claude_code_version"])
    ).replace("{{ opencode_version | quote }}", repr(values["opencode_version"]))
    assert "{{" not in rendered and "{%" not in rendered
    subprocess.run(["bash", "-n"], input=rendered, text=True, check=True)
    return rendered


def inventory() -> dict:
    result = subprocess.run(
        ["ansible-inventory", "-i", "inventory/hosts.yml", "--host", "xps"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def verify_dependency_policy(values: dict) -> None:
    for template in ROOT.rglob("*.j2"):
        assert "{#" not in template.read_text(), (
            f"{template.relative_to(ROOT)} contains a Jinja comment opener; "
            "use Bash syntax that cannot be parsed as an unterminated comment"
        )

    for group in ("github_release_apps", "nerd_font_apps"):
        for entry in values[group]:
            assert entry.get("version"), f"{entry['name']} has no release pin"
            assert SHA256.fullmatch(entry.get("checksum", "")), (
                f"{entry['name']} has no SHA-256 authorization"
            )

    assert re.fullmatch(r"[0-9a-f]{40}", values["lazyvim_starter_commit"])
    assert re.fullmatch(r"nightly-[0-9]{4}-[0-9]{2}-[0-9]{2}", values["rust_toolchain"])
    assert SEMVER.fullmatch(values["claude_code_version"])
    assert SEMVER.fullmatch(values["opencode_version"])
    assert not any(key.startswith("hermes_agent_") for key in values)
    assert "hermes_remote_url" not in values

    hermes_tasks = (ROOT / "roles/desktop/tasks/hermes-menubar.yml").read_text()
    assert "hermes-agent-removed-v1" in hermes_tasks
    assert '"{{ primary_home }}/.local/share/xps-user-tools/hermes"' in hermes_tasks
    assert '"{{ primary_home }}/.hermes"' in hermes_tasks
    assert '"{{ primary_home }}/.local/bin/hermes"' in hermes_tasks
    assert "raw.githubusercontent.com/NousResearch/hermes-agent" not in hermes_tasks
    assert not (ROOT / "roles/desktop/tasks/hermes-agent.yml").exists()
    assert not (
        ROOT / "roles/desktop/templates/hermes-backend.service.j2"
    ).exists()
    hermes_bridge_unit = (
        ROOT / "roles/desktop/templates/hermes-menubar-bridge.service.j2"
    ).read_text()
    assert "HERMES_REMOTE_URL" not in hermes_bridge_unit
    assert (
        "--remote-auth-state "
        "{{ primary_home }}/.local/state/hermes-menubar/remote-webui-auth.json"
        in hermes_bridge_unit
    )
    assert "--remote-only" in hermes_bridge_unit
    assert "--upstream" not in hermes_bridge_unit
    assert "hermes-backend.service" not in hermes_bridge_unit
    assert "EnvironmentFile=" not in hermes_bridge_unit
    assert "HERMES_REMOTE_PASSWORD" not in hermes_bridge_unit
    assert "HERMES_REMOTE_PASSWORD" not in (
        ROOT / "inventory/group_vars/all.yml"
    ).read_text()

    names = set()
    for entry in values["distrobox_images"]:
        assert entry["name"] not in names, f"duplicate Distrobox {entry['name']}"
        names.add(entry["name"])
        assert entry.get("source_tag"), f"{entry['name']} lacks review provenance"
        assert re.fullmatch(
            r"[^\s@]+@sha256:[0-9a-f]{64}", entry.get("image", "")
        ), f"{entry['name']} is not pinned to a manifest digest"

    dotfiles = (ROOT / "roles/dotfiles/tasks/main.yml").read_text()
    assert "version: main" not in dotfiles
    assert 'version: "{{ lazyvim_starter_commit }}"' in dotfiles
    assert 'loop: "{{ distrobox_images }}"' in dotfiles

    updater = (ROOT / "roles/apps/templates/update-user-tools.j2").read_text()
    assert "claude update" not in updater
    assert "opencode-ai@latest" not in updater
    assert 'claude install "$claude_pin"' in updater
    assert '"opencode-ai@$opencode_pin"' in updater
    assert 'mktemp -d "$root/.stage.' in updater
    render_user_updater(values)

    workflow = (ROOT / ".github/workflows/tests.yml").read_text()
    for package, purpose in (
        ("jq", "durable updater fixture"),
        ("dbus-daemon", "isolated QML runtime fixture"),
        ("luajit", "Hyprland Lua policy fixtures"),
        ("python3-websockets", "Hermes bridge protocol fixtures"),
    ):
        assert re.search(rf"^\s+{re.escape(package)} \\$", workflow, re.MULTILINE), (
            f"the clean Fedora CI container must explicitly install {package} "
            f"for the {purpose}"
        )
    action_refs = re.findall(r"^\s*- uses:\s*([^\s#]+)", workflow, re.MULTILINE)
    assert action_refs, "CI workflow has no externally reviewed actions"
    for action_ref in action_refs:
        assert re.fullmatch(r"[^@\s]+@[0-9a-f]{40}", action_ref), (
            f"CI action is not pinned to a full commit: {action_ref}"
        )

    runner = (ROOT / "tests/run").read_text()
    assert "rg -l '^#!.*(bash|sh)' -g '!*.j2' ." in runner
    assert "rg --files . -g '*.py'" in runner
    assert "rg -l '^#!.*python' -g '!*.j2' ." in runner

    fish = (ROOT / "roles/dotfiles/files/fish-config.fish").read_text()
    assert "alias codex='codex --dangerously-bypass-approvals-and-sandbox'" in fish
    assert "alias claude='claude --dangerously-skip-permissions'" in fish


def verify_user_updater_runtime(values: dict) -> None:
    rendered = render_user_updater(values)
    claude_pin = values["claude_code_version"]
    opencode_pin = values["opencode_version"]

    def run(home: Path) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment.update({"HOME": str(home), "PATH": "/usr/bin:/bin"})
        return subprocess.run(
            ["bash"], input=rendered, text=True, capture_output=True, env=environment
        )

    # Exact installed pins must be a true no-op and must not touch the network.
    with tempfile.TemporaryDirectory(prefix="fedora-config-user-tools.") as temporary:
        home = Path(temporary)
        executable(home / ".local/bin/claude", f'echo "{claude_pin} (Claude Code)"\n')
        executable(home / ".local/bin/opencode", f'echo "{opencode_pin}"\n')
        executable(home / ".local/bin/npm", 'echo "unexpected npm call" >&2; exit 99\n')
        executable(home / ".local/bin/curl", 'echo "unexpected curl call" >&2; exit 99\n')
        result = run(home)
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == "UNCHANGED: user-managed CLI pins"

    # A failed native Claude switch restores the exact prior version symlink.
    with tempfile.TemporaryDirectory(prefix="fedora-config-user-tools.") as temporary:
        home = Path(temporary)
        old = home / ".local/share/claude/versions/2.1.246"
        executable(
            old,
            'if [[ ${1:-} == --version ]]; then echo "2.1.246 (Claude Code)"; '
            'else exit 1; fi\n',
        )
        (home / ".local/bin").mkdir(parents=True)
        (home / ".local/bin/claude").symlink_to(old)
        executable(home / ".local/bin/opencode", f'echo "{opencode_pin}"\n')
        result = run(home)
        assert result.returncode == 75, (result.stdout, result.stderr)
        assert (home / ".local/bin/claude").resolve() == old
        assert "existing 2.1.246 retained" in result.stderr

    # A missing required tool is not a recoverable update failure merely
    # because the other tool already exists.
    with tempfile.TemporaryDirectory(prefix="fedora-config-user-tools.") as temporary:
        home = Path(temporary)
        executable(home / ".local/bin/opencode", f'echo "{opencode_pin}"\n')
        executable(home / ".local/bin/curl", 'exit 1\n')
        result = run(home)
        assert result.returncode == 1, (result.stdout, result.stderr)
        assert f"claude={claude_pin}" in result.stderr

    # OpenCode is built off to the side. A failed npm operation leaves the
    # legacy global installation untouched and reports the recoverable status.
    with tempfile.TemporaryDirectory(prefix="fedora-config-user-tools.") as temporary:
        home = Path(temporary)
        executable(home / ".local/bin/claude", f'echo "{claude_pin} (Claude Code)"\n')
        npm = home / ".local/bin/npm"
        executable(
            npm,
            'if [[ " $* " == *" list "* ]]; then '
            'echo \'{"dependencies":{"opencode-ai":{"version":"1.17.0"}}}\'; '
            'else exit 1; fi\n',
        )
        legacy = home / ".npm-global/retained-before-failure"
        legacy.parent.mkdir(parents=True)
        legacy.write_text("keep\n")
        result = run(home)
        assert result.returncode == 75, (result.stdout, result.stderr)
        assert legacy.read_text() == "keep\n"
        assert not (home / ".local/bin/opencode").exists()
        assert "existing 1.17.0 retained" in result.stderr

    # A successful staged install becomes visible only after its reported
    # version matches the pin; the legacy prefix remains available for rollback.
    with tempfile.TemporaryDirectory(prefix="fedora-config-user-tools.") as temporary:
        home = Path(temporary)
        executable(home / ".local/bin/claude", f'echo "{claude_pin} (Claude Code)"\n')
        executable(
            home / ".local/bin/npm",
            'if [[ " $* " == *" list "* ]]; then '
            'echo \'{"dependencies":{"opencode-ai":{"version":"1.17.0"}}}\'; exit 0; fi\n'
            'prefix=""; previous=""\n'
            'for argument in "$@"; do\n'
            '  if [[ $previous == --prefix ]]; then prefix=$argument; fi\n'
            '  previous=$argument\n'
            'done\n'
            'mkdir -p "$prefix/node_modules/.bin"\n'
            f'printf \'#!/usr/bin/env bash\\necho "{opencode_pin}"\\n\' '
            '> "$prefix/node_modules/.bin/opencode"\n'
            'chmod 0755 "$prefix/node_modules/.bin/opencode"\n',
        )
        legacy = home / ".npm-global/retained-before-success"
        legacy.parent.mkdir(parents=True)
        legacy.write_text("keep\n")
        result = run(home)
        assert result.returncode == 0, (result.stdout, result.stderr)
        assert result.stdout.strip() == "CHANGED: user-managed CLI update"
        assert legacy.read_text() == "keep\n"
        installed = subprocess.run(
            [str(home / ".local/bin/opencode")],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        assert installed == opencode_pin


def verify_asset_provenance() -> None:
    document = json.loads((ROOT / "assets/PROVENANCE.json").read_text())
    assert document["schemaVersion"] == 1
    assert document["rightsPolicy"]["status"] == "unknown-owner-action-required"
    records = {entry["path"]: entry for entry in document["assets"]}
    assert len(records) == len(document["assets"]), "duplicate provenance path"

    large_assets = {
        path.relative_to(ROOT).as_posix()
        for path in (ROOT / "assets").rglob("*")
        if path.is_file() and path.stat().st_size > 1024 * 1024
    }
    assert set(records) == large_assets, (
        f"provenance mismatch: missing={large_assets - set(records)}, "
        f"extra={set(records) - large_assets}"
    )
    for relative, record in records.items():
        path = ROOT / relative
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        assert record["sha256"] == digest, f"stale hash for {relative}"
        assert record["bytes"] == path.stat().st_size, f"stale size for {relative}"
        rights_status = record.get("rightsStatus", document["rightsPolicy"]["status"])
        if rights_status == "unknown-owner-action-required":
            assert record["creator"] is None
            assert record["sourceUrl"] is None
            assert record["license"] is None
        elif rights_status == "documented":
            assert all(
                isinstance(record[field], str) and record[field].strip()
                for field in ("creator", "sourceUrl", "license")
            ), f"incomplete documented rights for {relative}"
        else:
            raise AssertionError(f"unknown rights status for {relative}: {rights_status}")
        assert re.fullmatch(r"[0-9a-f]{40}", record["introducedByCommit"])


if __name__ == "__main__":
    values = inventory()
    verify_dependency_policy(values)
    verify_user_updater_runtime(values)
    verify_asset_provenance()
    print("dependency pins and large-asset provenance are internally consistent")
