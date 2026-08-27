#!/usr/bin/env python3
"""Deterministic auth, cache, and concurrency contracts for usage-fetch."""

from __future__ import annotations

import importlib.util
import json
import os
import stat
import threading
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "roles/desktop/files/quickshell/scripts/usage-fetch.py"
SPEC = importlib.util.spec_from_file_location("usage_fetch", PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FetchAllTests(unittest.TestCase):
    def test_providers_start_concurrently_and_keep_declared_order(self):
        barrier = threading.Barrier(3, timeout=1)

        def provider(name):
            def fetch():
                barrier.wait()
                return {"status": "ok", "name": name}

            return fetch

        providers = tuple((name, provider(name)) for name in ("a", "b", "c"))
        result = MODULE.fetch_all(providers)

        self.assertEqual(list(result), ["a", "b", "c"])
        self.assertEqual([value["status"] for value in result.values()], ["ok"] * 3)

    def test_one_provider_failure_does_not_hide_the_others(self):
        def broken():
            raise ValueError("malformed credentials")

        result = MODULE.fetch_all((
            ("good", lambda: {"status": "ok"}),
            ("bad", broken),
        ))

        self.assertEqual(result["good"], {"status": "ok"})
        self.assertEqual(result["bad"]["status"], "error")
        self.assertEqual(result["bad"]["kind"], "parse")
        self.assertIn("malformed credentials", result["bad"]["message"])


class ClaudeRefreshTests(unittest.TestCase):
    def test_refresh_is_delegated_to_cli_without_putting_token_in_arguments(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / ".credentials.json"
            oauth = {
                "accessToken": "expired-access",
                "expiresAt": 1,
                "refreshToken": "private-refresh-token",
                "refreshTokenExpiresAt": (time.time() + 3600) * 1000,
                "scopes": ["user:profile", "user:inference"],
            }
            path.write_text(json.dumps({"claudeAiOauth": oauth}))

            def run(command, **kwargs):
                self.assertEqual(command,
                                 ["/test/bin/claude", "auth", "login", "--claudeai"])
                self.assertNotIn("private-refresh-token", " ".join(command))
                self.assertEqual(kwargs["env"]["CLAUDE_CODE_OAUTH_REFRESH_TOKEN"],
                                 "private-refresh-token")
                self.assertEqual(kwargs["env"]["CLAUDE_CODE_OAUTH_SCOPES"],
                                 "user:profile user:inference")
                refreshed = dict(oauth, accessToken="fresh-access",
                                 expiresAt=(time.time() + 3600) * 1000)
                path.write_text(json.dumps({"claudeAiOauth": refreshed}))
                return mock.Mock(returncode=0, stdout=b"", stderr=b"")

            with mock.patch.object(MODULE.shutil, "which", return_value="/test/bin/claude"), \
                    mock.patch.object(MODULE.subprocess, "run", side_effect=run):
                refreshed, error = MODULE.refresh_claude_oauth(str(path), oauth)

            self.assertIsNone(error)
            self.assertEqual(refreshed["accessToken"], "fresh-access")

    def test_cli_failure_does_not_surface_captured_auth_output(self):
        oauth = {
            "accessToken": "expired-access",
            "refreshToken": "private-refresh-token",
            "refreshTokenExpiresAt": (time.time() + 3600) * 1000,
            "scopes": ["user:profile"],
        }
        completed = mock.Mock(returncode=1, stdout=b"private-refresh-token",
                              stderr=b"sensitive diagnostic")
        with mock.patch.object(MODULE.shutil, "which", return_value="/test/bin/claude"), \
                mock.patch.object(MODULE.subprocess, "run", return_value=completed):
            refreshed, error = MODULE.refresh_claude_oauth("/unused", oauth)

        self.assertIsNone(refreshed)
        self.assertEqual(error["kind"], "refresh")
        self.assertNotIn("private-refresh-token", json.dumps(error))
        self.assertNotIn("sensitive diagnostic", json.dumps(error))

    def test_expiring_access_token_uses_refresh_before_usage_request(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / ".credentials.json"
            expired = {"accessToken": "old", "expiresAt": 1,
                       "subscriptionType": "pro"}
            fresh = dict(expired, accessToken="fresh",
                         expiresAt=(time.time() + 3600) * 1000)
            path.write_text(json.dumps({"claudeAiOauth": expired}))

            def request(provider, url, headers):
                self.assertEqual(provider, "claude")
                self.assertEqual(headers["Authorization"], "Bearer fresh")
                return {"limits": []}, None

            with mock.patch.dict(os.environ, {
                    "CLAUDE_CONFIG_DIR": temporary, "HOME": temporary
                 }), \
                    mock.patch.object(MODULE, "refresh_claude_oauth",
                                      return_value=(fresh, None)) as refresh, \
                    mock.patch.object(MODULE, "http_json", side_effect=request):
                result = MODULE.fetch_claude(auto_refresh=True)

            refresh.assert_called_once_with(str(path), expired)
            self.assertEqual(result["status"], "ok")
            self.assertEqual(result["plan"], "Claude Pro")


class ResilientFetchTests(unittest.TestCase):
    @staticmethod
    def reading(reset=10_000):
        return {
            "status": "ok",
            "plan": "Test Pro",
            "windows": [{"label": "5 hour limit", "used": 25,
                         "resetsAt": reset}],
            "credits": None,
        }

    def test_success_is_cached_and_claude_observes_five_minute_floor(self):
        state = MODULE.empty_state()
        calls = 0

        def fetch():
            nonlocal calls
            calls += 1
            return self.reading()

        first = MODULE.fetch_all_resilient(
            (("claude", fetch),), state, now=1_000,
            min_intervals={"claude": 300})
        second = MODULE.fetch_all_resilient(
            (("claude", fetch),), state, now=1_100,
            min_intervals={"claude": 300})

        self.assertEqual(calls, 1)
        self.assertFalse(first["claude"]["stale"])
        self.assertFalse(second["claude"]["stale"])
        self.assertEqual(second["claude"]["observedAt"], 1_000)

    def test_failure_retains_last_good_and_honors_retry_after(self):
        state = MODULE.empty_state()
        MODULE.fetch_all_resilient(
            (("claude", lambda: self.reading()),), state, now=1_000,
            min_intervals={"claude": 300})
        calls = 0

        def limited():
            nonlocal calls
            calls += 1
            return MODULE.err("rate", "limited", retryAfter=600)

        failed = MODULE.fetch_all_resilient(
            (("claude", limited),), state, now=1_301,
            min_intervals={"claude": 300})
        backed_off = MODULE.fetch_all_resilient(
            (("claude", limited),), state, now=1_500,
            min_intervals={"claude": 300})

        self.assertEqual(calls, 1)
        self.assertEqual(failed["claude"]["status"], "ok")
        self.assertTrue(failed["claude"]["stale"])
        self.assertEqual(failed["claude"]["staleKind"], "rate")
        self.assertEqual(failed["claude"]["retryAt"], 1_901)
        self.assertEqual(backed_off["claude"]["retryAt"], 1_901)

    def test_stale_windows_are_removed_after_their_reset(self):
        entry = {
            "observedAt": 1_000,
            "lastOk": {
                "status": "ok",
                "windows": [
                    {"label": "old", "used": 99, "resetsAt": 1_100},
                    {"label": "current", "used": 20, "resetsAt": 2_000},
                ],
                "credits": None,
            },
        }
        failure = MODULE.err("network", "offline")
        cached = MODULE.cached_provider(entry, 1_200, failure, 1_500)
        self.assertEqual([window["label"] for window in cached["windows"]],
                         ["current"])

        entry["lastOk"]["windows"][1]["resetsAt"] = 1_150
        self.assertIsNone(MODULE.cached_provider(entry, 1_200, failure, 1_500))

    def test_retry_after_supports_seconds_and_http_dates(self):
        self.assertEqual(MODULE.retry_after_seconds({"Retry-After": "12"}, 1_000), 12)
        self.assertEqual(MODULE.retry_after_seconds(
            {"Retry-After": "Thu, 01 Jan 1970 00:17:00 GMT"}, 1_000), 20)
        self.assertEqual(MODULE.backoff_seconds(1, 300, {}), 300)
        self.assertEqual(MODULE.backoff_seconds(2, 0, {}), 120)
        self.assertEqual(MODULE.backoff_seconds(20, 0, {}), 900)

    def test_state_cache_is_private(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "nested" / "state.json"
            MODULE.save_state(str(path), MODULE.empty_state())
            self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)
            self.assertEqual(MODULE.load_state(str(path)), MODULE.empty_state())


if __name__ == "__main__":
    unittest.main()
