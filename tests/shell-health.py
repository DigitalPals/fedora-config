#!/usr/bin/env python3
"""Deterministic contracts for the bounded Shell Health helper."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "roles/desktop/files/quickshell/scripts/shell-health.py"
spec = importlib.util.spec_from_file_location("shell_health", SOURCE)
assert spec and spec.loader
shell_health = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shell_health)


def completed(stdout: str = "", returncode: int = 0) -> subprocess.CompletedProcess[str]:
    return subprocess.CompletedProcess([], returncode, stdout, "")


properties = "\n".join([
    "ActiveState=active",
    "MainPID=321",
    "ActiveEnterTimestampMonotonic=120000000",
    "InvocationID=0123456789abcdef0123456789abcdef",
])
with mock.patch.object(shell_health, "run", return_value=completed(properties)), \
        mock.patch.object(shell_health.time, "monotonic", return_value=125):
    service = shell_health.service_snapshot()
assert service == {
    "active": True,
    "pid": 321,
    "uptimeSecs": 5,
    "invocationId": "0123456789abcdef0123456789abcdef",
    "error": "",
}

with mock.patch.object(shell_health, "run", return_value=completed(
        "ActiveState=failed\nMainPID=not-a-number\n")):
    service = shell_health.service_snapshot()
assert service["active"] is False and service["pid"] == 0

home = str(Path.home())
journal = "\n".join([
    "not-json",
    json.dumps({"MESSAGE": "first"}),
    json.dumps({"MESSAGE": f"failed at {home}/private.qml"}),
    json.dumps({"MESSAGE": "https://user:password@example.test/a?token=secret"}),
    json.dumps({"MESSAGE": "x" * 300}),
])
with mock.patch.object(shell_health, "run", return_value=completed(journal)):
    warnings = shell_health.warning_snapshot("0123456789abcdef0123456789abcdef")
assert len(warnings) == 3
assert home not in " ".join(warnings)
assert "password" not in " ".join(warnings)
assert "secret" not in " ".join(warnings)
assert all(len(message) <= 240 for message in warnings)
assert warnings[-1].endswith("…")
assert shell_health.warning_snapshot("") == []

for message in (
    "Authorization: Bearer header-secret",
    "helper --token cli-secret failed",
    '{"api_key":"json-secret"}',
    "JWT eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJwcml2YXRlIn0.signature",
    "provider sk-this-is-a-private-key",
):
    safe = shell_health.safe_message(message)
    assert "secret" not in safe
    assert "private" not in safe
    assert "eyJ" not in safe

with mock.patch.object(
        shell_health.subprocess, "run", side_effect=subprocess.TimeoutExpired([], 4)):
    assert shell_health.run(["slow"]).returncode == 124
with mock.patch.object(shell_health.subprocess, "run", side_effect=FileNotFoundError()):
    assert shell_health.run(["missing"]).returncode == 127

print("Shell health parsing, redaction, and bounds passed")
