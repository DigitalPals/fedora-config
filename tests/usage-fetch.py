#!/usr/bin/env python3
"""Deterministic auth, cache, and concurrency contracts for usage-fetch."""

from __future__ import annotations

import importlib.util
import json
import os
import stat
import subprocess
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

CREDENTIAL_PATH = (ROOT / "roles/desktop/files/quickshell/scripts/"
                   "usage-credential.py")


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


class ClaudePlanTests(unittest.TestCase):
    def test_max_tier_includes_its_usage_multiplier(self):
        self.assertEqual(MODULE.claude_plan({
            "subscriptionType": "max",
            "rateLimitTier": "default_claude_max_20x",
        }), "Claude Max 20x")
        self.assertEqual(MODULE.claude_plan({
            "subscriptionType": "max",
            "rateLimitTier": "default-claude-max-5x",
        }), "Claude Max 5x")

    def test_non_max_and_unknown_tiers_fall_back_to_subscription(self):
        self.assertEqual(MODULE.claude_plan({
            "subscriptionType": "pro",
            "rateLimitTier": "default_claude_pro",
        }), "Claude Pro")
        self.assertEqual(MODULE.claude_plan({
            "subscriptionType": "max",
            "rateLimitTier": "future_tier_name",
        }), "Claude Max")

    def test_cached_label_updates_and_identity_metadata_is_removed(self):
        state = {
            "version": MODULE.STATE_VERSION,
            "providers": {"claude": {"lastOk": {
                "status": "ok",
                "plan": "Claude Max",
                "account": "private@example.test",
                "source": "claude-oauth",
            }}},
        }
        with tempfile.TemporaryDirectory() as temporary:
            credential_dir = Path(temporary) / ".claude"
            credential_dir.mkdir()
            credential_dir.joinpath(".credentials.json").write_text(json.dumps({
                "claudeAiOauth": {
                    "accessToken": "unused",
                    "subscriptionType": "max",
                    "rateLimitTier": "default_claude_max_20x",
                }
            }))
            with mock.patch.dict(os.environ, {"HOME": temporary}, clear=False):
                MODULE.update_cached_claude_metadata(state)

        cached = state["providers"]["claude"]["lastOk"]
        self.assertEqual(cached["plan"], "Claude Max 20x")
        self.assertNotIn("account", cached)
        self.assertNotIn("source", cached)


class XaiUsageTests(unittest.TestCase):
    def test_weekly_period_without_percentage_remains_unknown(self):
        result = MODULE.parse_xai_usage({"config": {
            "currentPeriod": {
                "type": "USAGE_PERIOD_TYPE_WEEKLY",
                "start": "2026-09-03T05:37:29+00:00",
                "end": "2026-09-10T05:37:29+00:00",
            },
        }}, {"config": {
            "monthlyLimit": {"val": 0},
            "used": {"val": 0},
            "onDemandCap": {"val": 0},
        }})

        self.assertEqual(result["status"], "ok")
        self.assertEqual(len(result["windows"]), 1)
        self.assertIsNone(result["windows"][0]["used"])
        self.assertEqual(result["windows"][0]["windowSecs"], MODULE.SEVEN_DAYS)
        self.assertEqual(result["windows"][0]["resetsAt"],
                         MODULE.parse_rfc3339("2026-09-10T05:37:29+00:00"))
        self.assertIsNone(result["credits"])

    def test_percent_products_plan_and_monthly_credits_are_normalized(self):
        result = MODULE.parse_xai_usage({"config": {
            "current_period": {
                "type": "weekly",
                "start": "2026-09-03T05:37:29Z",
                "end": "2026-09-10T05:37:29Z",
            },
            "credit_usage_percent": "31.25",
            "product_usage": [
                {"product": "Grok Code", "usage_percent": "80"},
            ],
        }}, {"config": {
            "monthly_limit": {"val": 15_000},
            "used": {"val": 2_500},
        }})

        self.assertEqual(result["plan"], "SuperGrok")
        self.assertEqual([row["used"] for row in result["windows"]],
                         [31.25, 80.0])
        self.assertEqual(result["windows"][1]["label"], "Grok Code usage")
        self.assertEqual(result["credits"]["label"], "Monthly credits")
        self.assertEqual(result["credits"]["used"], 25)
        self.assertEqual(result["credits"]["limit"], 150)


class CliProxyTests(unittest.TestCase):
    def test_dashboard_and_management_urls_normalize_to_server_base(self):
        self.assertEqual(MODULE.normalize_cliproxy_url(
            "https://10.10.0.235:8317/management.html"),
            "https://10.10.0.235:8317")
        self.assertEqual(MODULE.normalize_cliproxy_url(
            "https://proxy.test/prefix/v0/management/"),
            "https://proxy.test/prefix")
        with self.assertRaises(ValueError):
            MODULE.normalize_cliproxy_url("https://user:secret@proxy.test")

    def test_management_key_reader_rejects_broad_permissions(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "key"
            path.write_text("management-secret\n")
            path.chmod(0o600)
            key, failure = MODULE.read_cliproxy_key(str(path))
            self.assertEqual(key, "management-secret")
            self.assertIsNone(failure)

            path.chmod(0o644)
            key, failure = MODULE.read_cliproxy_key(str(path))
            self.assertIsNone(key)
            self.assertEqual(failure["kind"], "config")

    def test_api_call_uses_auth_index_and_token_placeholder(self):
        calls = []

        def request(url, headers, method, body, ssl_context):
            calls.append((url, headers, method, json.loads(body)))
            response = {"status_code": 200, "body": json.dumps({"limits": []})}
            return 200, json.dumps(response).encode(), {}

        client = MODULE.CliProxyClient("https://proxy.test/management.html",
                                       "management-secret", verify_tls=False)
        with mock.patch.object(MODULE, "http_request", side_effect=request):
            data, failure = client.api_json("auth-17", "https://upstream.test/usage", {
                "Authorization": "Bearer $TOKEN$",
            })

        self.assertIsNone(failure)
        self.assertEqual(data, {"limits": []})
        url, headers, method, payload = calls[0]
        self.assertEqual(url, "https://proxy.test/v0/management/api-call")
        self.assertEqual(method, "POST")
        self.assertEqual(headers["Authorization"], "Bearer management-secret")
        self.assertEqual(payload["auth_index"], "auth-17")
        self.assertEqual(payload["header"]["Authorization"], "Bearer $TOKEN$")

    def test_account_pool_keeps_every_subscription_and_best_summary(self):
        entries = [
            {"provider": "codex", "auth_index": "full",
             "email": "first@example.test", "label": "first@example.test"},
            {"provider": "codex", "auth_index": "open",
             "email": "second@example.test", "label": "second@example.test"},
            {"provider": "codex", "auth_index": "broken",
             "email": "third@example.test", "label": "third@example.test"},
        ]

        def account(provider, entry, client):
            if entry["auth_index"] == "broken":
                return MODULE.err("expired", "rejected")
            used = 90 if entry["auth_index"] == "full" else 20
            return {"status": "ok", "plan": "ChatGPT Plus",
                    "account": "private@example.test",
                    "windows": [{"label": "5 hour limit", "used": used}],
                    "credits": None}

        with mock.patch.object(MODULE, "fetch_cliproxy_account", side_effect=account):
            result = MODULE.fetch_cliproxy_provider("codex", entries, object())

        self.assertEqual(result["windows"][0]["used"], 20)
        self.assertEqual(result["source"], "cliproxy")
        self.assertEqual(result["accountCount"], 3)
        self.assertEqual(result["availableCount"], 2)
        self.assertEqual(result["plan"], "ChatGPT Plus")
        self.assertEqual(len(result["accounts"]), 3)
        self.assertEqual([account["status"] for account in result["accounts"]],
                         ["ok", "ok", "error"])
        self.assertEqual([account["label"] for account in result["accounts"]],
                         ["f•••@example.test", "s•••@example.test",
                          "t•••@example.test"])
        self.assertEqual(result["bestAccountId"], result["accounts"][1]["id"])
        self.assertNotIn("account", result)
        serialized = json.dumps(result)
        for private in ("private@example.test", "first@example.test",
                        "second@example.test", "third@example.test",
                        "full", "open", "broken"):
            self.assertNotIn(private, serialized)

    def test_account_pool_preserves_each_failure_when_all_accounts_fail(self):
        entries = [
            {"provider": "claude", "auth_index": "one",
             "email": "one@example.test"},
            {"provider": "claude", "auth_index": "two",
             "email": "two@example.test"},
        ]

        def account(provider, entry, client):
            kind = "expired" if entry["auth_index"] == "one" else "rate"
            return MODULE.err(kind, kind + " account")

        with mock.patch.object(MODULE, "fetch_cliproxy_account", side_effect=account):
            result = MODULE.fetch_cliproxy_provider("claude", entries, object())

        self.assertEqual(result["status"], "error")
        self.assertEqual(result["kind"], "expired")
        self.assertEqual(result["source"], "cliproxy")
        self.assertEqual(result["accountCount"], 2)
        self.assertEqual(result["availableCount"], 0)
        self.assertEqual([account["kind"] for account in result["accounts"]],
                         ["expired", "rate"])

    def test_absent_provider_is_not_marked_as_managed_by_cliproxy(self):
        result = MODULE.fetch_cliproxy_provider("kimi", [{
            "provider": "codex", "auth_index": "codex-only",
        }], object())

        self.assertEqual(result["status"], "error")
        self.assertEqual(result["kind"], "nocreds")
        self.assertNotIn("source", result)

    def test_custom_account_label_is_kept_but_email_labels_are_masked(self):
        self.assertEqual(MODULE.cliproxy_account_label({
            "email": "private@example.test", "label": "Work subscription",
        }, 0), "Work subscription")
        self.assertEqual(MODULE.cliproxy_account_label({
            "label": "private@example.test",
        }, 0), "p•••@example.test")
        self.assertEqual(MODULE.cliproxy_account_label({}, 1), "Account 2")

        readings = [{"label": "Shared"}, {"label": "Shared"},
                    {"label": "Personal"}]
        MODULE.disambiguate_cliproxy_labels(readings)
        self.assertEqual([reading["label"] for reading in readings],
                         ["Shared · 1", "Shared · 2", "Personal"])

    def test_xai_account_uses_only_the_two_read_only_billing_endpoints(self):
        calls = []

        class Client:
            def api_json(self, auth_index, url, headers):
                calls.append((auth_index, url, dict(headers)))
                if url == MODULE.XAI_BILLING_WEEKLY_URL:
                    return {"config": {
                        "currentPeriod": {"type": "weekly"},
                        "creditUsagePercent": 12,
                    }}, None
                return {"config": {
                    "monthlyLimit": {"val": 15_000},
                    "used": {"val": 3_000},
                }}, None

        result = MODULE.fetch_cliproxy_account(
            "xai", {"auth_index": "xai-9"}, Client())

        self.assertEqual(result["status"], "ok")
        self.assertEqual({call[1] for call in calls}, {
            MODULE.XAI_BILLING_WEEKLY_URL,
            MODULE.XAI_BILLING_MONTHLY_URL,
        })
        self.assertTrue(all(call[0] == "xai-9" for call in calls))
        self.assertTrue(all(call[2]["Authorization"] == "Bearer $TOKEN$"
                            for call in calls))
        self.assertTrue(all("chat/completions" not in call[1] for call in calls))


class CliProxyCredentialHelperTests(unittest.TestCase):
    def test_store_status_and_clear_keep_the_key_private_and_out_of_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "private" / "management.key"
            environment = dict(os.environ,
                QUICKSHELL_USAGE_CLIPROXY_KEY_PATH=str(path))
            secret = b"not-a-real-management-secret"
            stored = subprocess.run(
                [str(CREDENTIAL_PATH), "store"], input=secret,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                env=environment, check=False)
            self.assertEqual(stored.returncode, 0, stored.stderr)
            self.assertNotIn(secret, stored.stdout)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(json.loads(stored.stdout),
                             {"success": True, "configured": True})

            cleared = subprocess.run(
                [str(CREDENTIAL_PATH), "clear"], stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, env=environment, check=False)
            self.assertEqual(cleared.returncode, 0, cleared.stderr)
            self.assertFalse(path.exists())


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

    def test_cached_pool_marks_accounts_stale_and_prunes_their_windows(self):
        entry = {
            "observedAt": 1_000,
            "lastOk": {
                "status": "ok",
                "windows": [{"label": "summary", "used": 20,
                             "resetsAt": 2_000}],
                "credits": None,
                "accounts": [{
                    "id": "account-safe", "label": "p•••@example.test",
                    "status": "ok", "windows": [
                        {"label": "old", "used": 90, "resetsAt": 1_100},
                        {"label": "current", "used": 25,
                         "resetsAt": 2_000},
                    ],
                    "credits": None,
                }],
            },
        }
        failure = MODULE.err("network", "offline")

        cached = MODULE.cached_provider(entry, 1_200, failure, 1_500)

        account = cached["accounts"][0]
        self.assertEqual([window["label"] for window in account["windows"]],
                         ["current"])
        self.assertTrue(account["stale"])
        self.assertEqual(account["staleKind"], "network")
        self.assertEqual(account["observedAt"], 1_000)

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
