#!/usr/bin/env python3
"""Deterministic concurrency/error contracts for the usage provider helper."""

from __future__ import annotations

import importlib.util
import threading
import unittest
from pathlib import Path


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


if __name__ == "__main__":
    unittest.main()
