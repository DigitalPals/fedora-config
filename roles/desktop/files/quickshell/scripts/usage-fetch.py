#!/usr/bin/env python3
"""Model-usage fetcher for the Quickshell menubar.

Reads the credential files the provider CLIs (Claude Code, Codex CLI, Kimi
Code) write locally and polls each provider's own usage endpoint.  With
``--refresh-claude``, an expiring Claude access token is handed back to the
official Claude CLI for refresh; this helper never implements OAuth or writes
Claude's credential file itself.

Successful readings are cached privately.  Endpoint failures retain a marked
stale reading until its reset passes, and repeated failures back off instead
of hammering a rate-limited endpoint.

Prints one JSON object: {"claude": {...}, "codex": {...}, "kimi": {...}}
Each provider is {"status": "ok", ...} or {"status": "error", "kind": ...}.
"""

import argparse
import base64
import copy
import fcntl
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

TIMEOUT = 20
REFRESH_TIMEOUT = 30

FIVE_HOURS = 5 * 3600
SEVEN_DAYS = 7 * 24 * 3600
CLAUDE_MIN_INTERVAL = 5 * 60
MAX_BACKOFF = 15 * 60
MAX_STALE_AGE = 2 * 24 * 3600
STATE_VERSION = 1


def home(*parts):
    return os.path.join(os.path.expanduser("~"), *parts)


def read_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def err(kind, message="", **details):
    value = {"status": "error", "kind": kind, "message": message}
    value.update(details)
    return value


def http_get(url, headers):
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return resp.status, resp.read(), resp.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read(), e.headers
    except Exception as e:  # DNS, timeout, TLS…
        return None, str(e), {}


def retry_after_seconds(headers, now=None):
    """Parse Retry-After's seconds or HTTP-date forms."""
    raw = headers.get("Retry-After") if headers else None
    if not isinstance(raw, str):
        return None
    raw = raw.strip()
    if not raw:
        return None
    try:
        return max(0, math.ceil(float(raw)))
    except (ValueError, OverflowError):
        pass
    try:
        parsed = parsedate_to_datetime(raw)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        current = time.time() if now is None else now
        return max(0, math.ceil(parsed.timestamp() - current))
    except (TypeError, ValueError, OverflowError):
        return None


def http_json(provider_cmd, url, headers):
    """Shared fetch + status handling. Returns (data, None) or (None, err)."""
    status, body, response_headers = http_get(url, headers)
    if status is None:
        return None, err("network", body)
    if status == 429:
        return None, err("rate", "Rate limited by the usage endpoint.",
                         retryAfter=retry_after_seconds(response_headers))
    if status in (401, 403):
        return None, err("expired", provider_cmd)
    if not 200 <= status < 300:
        return None, err("http", f"Usage endpoint returned HTTP {status}.")
    try:
        return json.loads(body), None
    except Exception as e:
        return None, err("parse", str(e))


def parse_rfc3339(value):
    if not isinstance(value, str):
        return None
    try:
        text = value.replace("Z", "+00:00")
        return int(datetime.fromisoformat(text).timestamp())
    except ValueError:
        return None


def lenient_num(value):
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value.strip())
        except ValueError:
            return None
    return None


def jwt_claims(token):
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        return json.loads(base64.urlsafe_b64decode(payload))
    except Exception:
        return {}


# ---------------------------------------------------------------- State/cache

def usage_state_path():
    override = os.environ.get("QUICKSHELL_USAGE_STATE_PATH")
    if override:
        return os.path.abspath(os.path.expanduser(override))
    cache_home = os.environ.get("XDG_CACHE_HOME")
    if not cache_home:
        cache_home = home(".cache")
    return os.path.join(os.path.expanduser(cache_home), "quickshell",
                        "model-usage.json")


def empty_state():
    return {"version": STATE_VERSION, "providers": {}}


def load_state(path):
    try:
        value = read_json(path)
    except (OSError, ValueError, TypeError):
        return empty_state()
    if not isinstance(value, dict) or value.get("version") != STATE_VERSION:
        return empty_state()
    if not isinstance(value.get("providers"), dict):
        value["providers"] = {}
    return value


def save_state(path, state):
    """Atomically write a user-private cache without following a file link."""
    directory = os.path.dirname(path)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".model-usage-", dir=directory)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fd = -1
            json.dump(state, fh, separators=(",", ":"))
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(temporary, path)
        os.chmod(path, 0o600, follow_symlinks=False)
    finally:
        if fd >= 0:
            os.close(fd)
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def cached_provider(entry, now, failure=None, retry_at=None):
    """Return a safe cached reading, dropping windows whose reset passed."""
    if not isinstance(entry, dict):
        return None
    value = entry.get("lastOk")
    observed_at = entry.get("observedAt")
    if not isinstance(value, dict) or value.get("status") != "ok":
        return None
    if not isinstance(observed_at, (int, float)):
        return None
    if now - observed_at > MAX_STALE_AGE:
        return None

    cached = copy.deepcopy(value)
    previous_windows = cached.get("windows")
    if isinstance(previous_windows, list):
        cached["windows"] = [window for window in previous_windows
                             if not isinstance(window, dict)
                             or not isinstance(window.get("resetsAt"), (int, float))
                             or window["resetsAt"] > now]
        # A quota percentage belongs to the period in which it was observed.
        # Once every known period resets, do not present that number as current.
        if previous_windows and not cached["windows"] and not cached.get("credits"):
            return None

    cached["observedAt"] = int(observed_at)
    cached["stale"] = failure is not None
    if failure is not None:
        cached["staleKind"] = failure.get("kind", "network")
        cached["staleMessage"] = failure.get("message", "")
        if isinstance(retry_at, (int, float)):
            cached["retryAt"] = int(retry_at)
    return cached


def backoff_seconds(failures, minimum, failure):
    delay = min(MAX_BACKOFF, 60 * (2 ** max(0, failures - 1)))
    delay = max(minimum, delay)
    retry_after = failure.get("retryAfter")
    if isinstance(retry_after, (int, float)) and math.isfinite(retry_after):
        delay = max(delay, math.ceil(retry_after))
    return delay


# ---------------------------------------------------------------- Claude

CLAUDE_PLANS = {"pro": "Claude Pro", "max": "Claude Max", "team": "Claude Team",
                "enterprise": "Claude Enterprise"}


def token_expired(value, now=None, skew=0):
    if not isinstance(value, (int, float)):
        return False
    # Claude's credential file currently stores milliseconds, while accepting
    # seconds here keeps the check tolerant of a future schema change.
    timestamp = value / 1000 if value > 10_000_000_000 else value
    current = time.time() if now is None else now
    return timestamp <= current + skew


def read_claude_oauth(path):
    try:
        oauth = read_json(path)["claudeAiOauth"]
        if not isinstance(oauth, dict) or not isinstance(oauth.get("accessToken"), str):
            return None
        return oauth
    except (OSError, ValueError, TypeError, KeyError):
        return None


def refresh_claude_oauth(path, oauth):
    """Ask Claude Code to exchange its own refresh token and rewrite creds."""
    refresh_token = oauth.get("refreshToken")
    scopes = oauth.get("scopes")
    if isinstance(scopes, list):
        scopes = " ".join(scope for scope in scopes if isinstance(scope, str))
    elif isinstance(scopes, str):
        scopes = " ".join(scopes.split())
    else:
        scopes = ""
    if (not isinstance(refresh_token, str) or not refresh_token
            or not scopes or token_expired(oauth.get("refreshTokenExpiresAt"))):
        return None, err("expired", "claude")

    executable = shutil.which("claude")
    if not executable:
        return None, err("refresh", "Claude Code is not installed or not on PATH.")

    environment = os.environ.copy()
    # Subscription login must not be pre-empted by a terminal API key, cloud
    # provider, or access-token override inherited by quickshell.service.
    for name in ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN",
                 "CLAUDE_CODE_OAUTH_TOKEN",
                 "CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR",
                 "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX",
                 "CLAUDE_CODE_USE_FOUNDRY"):
        environment.pop(name, None)
    environment["CLAUDE_CODE_OAUTH_REFRESH_TOKEN"] = refresh_token
    environment["CLAUDE_CODE_OAUTH_SCOPES"] = scopes
    environment["NO_COLOR"] = "1"

    try:
        completed = subprocess.run(
            [executable, "auth", "login", "--claudeai"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
            timeout=REFRESH_TIMEOUT,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return None, err("refresh", "Claude Code token refresh timed out.")
    except OSError:
        return None, err("refresh", "Claude Code token refresh could not start.")
    if completed.returncode != 0:
        # Deliberately do not surface CLI output: authentication diagnostics
        # are not guaranteed to be free of credential material.
        return None, err("refresh", "Claude Code could not refresh the saved login.")

    refreshed = read_claude_oauth(path)
    if not refreshed or token_expired(refreshed.get("expiresAt"), skew=60):
        return None, err("refresh", "Claude Code did not save a fresh login.")
    return refreshed, None


def claude_limit_window(raw):
    """Convert the current structured Claude usage rows into UI windows."""
    if not isinstance(raw, dict):
        return None
    used = lenient_num(raw.get("percent"))
    if used is None:
        return None

    kind = raw.get("kind") or ""
    group = raw.get("group") or ""
    scope = raw.get("scope") if isinstance(raw.get("scope"), dict) else {}

    scoped_name = None
    for scope_kind in ("model", "surface"):
        scoped = scope.get(scope_kind)
        if isinstance(scoped, dict):
            scoped_name = scoped.get("display_name") or scoped.get("name")
        elif isinstance(scoped, str):
            scoped_name = scoped
        if scoped_name:
            break

    if kind == "session" or group == "session":
        label = "5 hour limit"
        window_secs = FIVE_HOURS
    elif kind == "weekly_scoped" and scoped_name:
        label = f"Weekly ({scoped_name})"
        window_secs = SEVEN_DAYS
    elif kind.startswith("weekly") or group == "weekly":
        label = "Weekly limit"
        window_secs = SEVEN_DAYS
    else:
        label = scoped_name or kind.replace("_", " ").strip().title() or "Usage limit"
        window_secs = None

    return {"label": label, "used": min(max(used, 0.0), 100.0),
            "windowSecs": window_secs,
            "resetsAt": parse_rfc3339(raw.get("resets_at"))}


def fetch_claude(auto_refresh=False):
    cfg_dir = os.environ.get("CLAUDE_CONFIG_DIR") or home(".claude")
    path = os.path.join(cfg_dir, ".credentials.json")
    if not os.path.isfile(path):
        return err("nocreds", "claude")
    oauth = read_claude_oauth(path)
    if not oauth:
        return err("nocreds", "claude")
    refreshed = False
    if token_expired(oauth.get("expiresAt"), skew=60):
        if not auto_refresh:
            return err("expired", "claude")
        oauth, refresh_error = refresh_claude_oauth(path, oauth)
        if refresh_error:
            return refresh_error
        refreshed = True
    token = oauth["accessToken"]

    plan = CLAUDE_PLANS.get(oauth.get("subscriptionType"), oauth.get("subscriptionType"))
    account = None
    try:
        account = read_json(home(".claude.json"))["oauthAccount"]["emailAddress"]
    except Exception:
        pass

    data, e = http_json("claude", "https://api.anthropic.com/api/oauth/usage", {
        "Authorization": f"Bearer {token}",
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "claude-code/2.1.0 (external, cli)",
    })
    # Expiry metadata can lag server-side revocation. Give the CLI one chance
    # to refresh and retry, but never loop on a rejected replacement token.
    if e and e.get("kind") == "expired" and auto_refresh and not refreshed:
        oauth, refresh_error = refresh_claude_oauth(path, oauth)
        if refresh_error:
            return refresh_error
        data, e = http_json("claude", "https://api.anthropic.com/api/oauth/usage", {
            "Authorization": f"Bearer {oauth['accessToken']}",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "claude-code/2.1.0 (external, cli)",
        })
    if e:
        return e

    # Newer Claude usage responses expose a structured list, including
    # account-specific scoped limits such as Fable. Prefer it so new model
    # limits appear automatically without hard-coding their API field names.
    windows = [window for window in
               (claude_limit_window(row) for row in data.get("limits") or [])
               if window]

    # Compatibility with older endpoint responses.
    if not windows:
        for key, label, secs in (("five_hour", "5 hour limit", FIVE_HOURS),
                                 ("seven_day", "Weekly limit", SEVEN_DAYS),
                                 ("seven_day_opus", "Weekly (Opus)", SEVEN_DAYS),
                                 ("seven_day_sonnet", "Weekly (Sonnet)", SEVEN_DAYS)):
            raw = data.get(key)
            if not isinstance(raw, dict):
                continue
            used = raw.get("utilization")
            if not isinstance(used, (int, float)):
                continue
            windows.append({"label": label,
                            "used": min(max(float(used), 0.0), 100.0),
                            "windowSecs": secs,
                            "resetsAt": parse_rfc3339(raw.get("resets_at"))})

    credits = None
    extra = data.get("extra_usage")
    if isinstance(extra, dict) and extra.get("is_enabled"):
        # Monetary amounts arrive in cents.
        used = lenient_num(extra.get("used_credits"))
        limit = lenient_num(extra.get("monthly_limit"))
        credits = {"used": used / 100 if used is not None else None,
                   "limit": limit / 100 if limit is not None else None,
                   "currency": extra.get("currency"),
                   "unlimited": False}

    return {"status": "ok", "plan": plan, "account": account,
            "source": "claude-oauth", "windows": windows, "credits": credits}


# ---------------------------------------------------------------- Codex

CODEX_PLANS = {"plus": "ChatGPT Plus", "pro": "ChatGPT Pro", "team": "ChatGPT Team",
               "business": "ChatGPT Business", "enterprise": "ChatGPT Enterprise",
               "free": "ChatGPT Free"}


def codex_window(raw, model):
    used = raw.get("used_percent")
    if not isinstance(used, (int, float)):
        return None
    secs = raw.get("limit_window_seconds")
    if model:
        span = "usage"
        if isinstance(secs, (int, float)):
            span = "5 hour" if secs <= FIVE_HOURS else humanize_window(int(secs))
        label = f"{model} ({span})"
    elif isinstance(secs, (int, float)) and secs <= FIVE_HOURS:
        label = "5 hour limit"
    elif secs == SEVEN_DAYS:
        label = "Weekly limit"
    elif isinstance(secs, (int, float)):
        label = f"{humanize_window(int(secs))} limit"
    else:
        label = "usage limit"

    reset = raw.get("reset_at")
    resets_at = int(reset) if isinstance(reset, (int, float)) else parse_rfc3339(reset)
    return {"label": label, "used": min(max(float(used), 0.0), 100.0),
            "windowSecs": int(secs) if isinstance(secs, (int, float)) else None,
            "resetsAt": resets_at}


def humanize_window(secs):
    hours = secs // 3600
    if hours >= 24 and hours % 24 == 0:
        return f"{hours // 24} day"
    return f"{hours} hour"


def fetch_codex():
    codex_home = os.environ.get("CODEX_HOME") or home(".codex")
    path = os.path.join(codex_home, "auth.json")
    if not os.path.isfile(path):
        return err("nocreds", "codex")
    try:
        tokens = read_json(path).get("tokens")
    except Exception:
        return err("nocreds", "codex")
    if not tokens or "access_token" not in tokens:
        return err("nocreds", "codex")

    claims = jwt_claims(tokens.get("id_token") or "")
    auth_claims = claims.get("https://api.openai.com/auth") or {}
    plan = CODEX_PLANS.get(auth_claims.get("chatgpt_plan_type"),
                           auth_claims.get("chatgpt_plan_type"))
    email = claims.get("email")

    headers = {"Authorization": f"Bearer {tokens['access_token']}",
               "User-Agent": "codex-cli"}
    if tokens.get("account_id"):
        headers["ChatGPT-Account-Id"] = tokens["account_id"]
    data, e = http_json("codex", "https://chatgpt.com/backend-api/wham/usage", headers)
    if e:
        return e

    windows = []
    def push(rate_limit, model=None):
        if not isinstance(rate_limit, dict):
            return
        for key in ("primary_window", "secondary_window"):
            raw = rate_limit.get(key)
            if isinstance(raw, dict):
                w = codex_window(raw, model)
                if w:
                    windows.append(w)

    push(data.get("rate_limit"))
    for extra in data.get("additional_rate_limits") or []:
        if isinstance(extra, dict):
            push(extra.get("rate_limit"), extra.get("limit_name"))

    if plan is None and data.get("plan_type"):
        plan = f"ChatGPT {data['plan_type']}"
    email = email or data.get("email")

    credits = None
    raw_credits = data.get("credits")
    if isinstance(raw_credits, dict) and (raw_credits.get("has_credits")
                                          or raw_credits.get("unlimited")):
        credits = {"remaining": lenient_num(raw_credits.get("balance")),
                   "unlimited": bool(raw_credits.get("unlimited"))}

    return {"status": "ok", "plan": plan, "account": email,
            "source": "codex-oauth", "windows": windows, "credits": credits}


# ---------------------------------------------------------------- Kimi

def kimi_window_secs(window):
    if not isinstance(window, dict):
        return None
    duration = lenient_num(window.get("duration"))
    if duration is None:
        return None
    unit = (window.get("timeUnit") or "").upper()
    scale = {"TIME_UNIT_SECOND": 1, "TIME_UNIT_MINUTE": 60,
             "TIME_UNIT_HOUR": 3600, "TIME_UNIT_DAY": 86400}.get(unit)
    return int(duration * scale) if scale else None


def kimi_row(counters, window_secs, fallback_label):
    used = lenient_num(counters.get("used"))
    limit = lenient_num(counters.get("limit"))
    remaining = lenient_num(counters.get("remaining"))
    if used is None and limit is not None and remaining is not None:
        used = limit - remaining
    if used is None or not limit:
        return None
    pct = min(max(used / limit * 100.0, 0.0), 100.0)
    resets_at = parse_rfc3339(counters.get("reset_at") or counters.get("resetAt")
                              or counters.get("reset_time") or counters.get("resetTime"))
    if resets_at is None:
        reset_in = lenient_num(counters.get("reset_in") or counters.get("resetIn")
                               or counters.get("ttl"))
        if reset_in is not None:
            resets_at = int(time.time() + reset_in)
    label = counters.get("title") or counters.get("name") or fallback_label
    return {"label": label, "used": pct, "windowSecs": window_secs, "resetsAt": resets_at}


def fetch_kimi():
    kimi_home = os.environ.get("KIMI_CODE_HOME") or home(".kimi-code")
    path = os.path.join(kimi_home, "credentials", "kimi-code.json")
    if not os.path.isfile(path):
        return err("nocreds", "kimi")
    try:
        creds = read_json(path)
        token = creds["access_token"]
    except Exception:
        return err("nocreds", "kimi")
    expires_at = creds.get("expires_at")
    if isinstance(expires_at, (int, float)) and expires_at <= time.time():
        return err("expired", "kimi")

    base = (os.environ.get("KIMI_CODE_BASE_URL") or "https://api.kimi.com/coding/v1").rstrip("/")
    data, e = http_json("kimi", f"{base}/usages", {
        "Authorization": f"Bearer {token}", "Accept": "application/json"})
    if e:
        return e

    windows = []
    usage = data.get("usage")
    if isinstance(usage, dict):
        w = kimi_row(usage, SEVEN_DAYS, "Weekly limit")
        if w:
            windows.append(w)
    for limit in data.get("limits") or []:
        if not isinstance(limit, dict):
            continue
        counters = limit.get("detail") if isinstance(limit.get("detail"), dict) else limit
        secs = kimi_window_secs(limit.get("window"))
        fallback = "5 hour limit" if secs == FIVE_HOURS else "Usage limit"
        w = kimi_row(counters, secs, fallback)
        if w:
            windows.append(w)

    plan = None
    membership = (data.get("user") or {}).get("membership") or {}
    level = membership.get("level")
    if isinstance(level, str):
        plan = "Kimi " + level.replace("LEVEL_", "").replace("_", " ").title()

    credits = None
    wallet = data.get("boosterWallet")
    if isinstance(wallet, dict):
        balance = wallet.get("balance") or {}
        # amount fields are fixed-point micro-cents: raw / 1e6 = cents.
        left = lenient_num(balance.get("amountLeft"))
        used = lenient_num((wallet.get("monthlyUsed") or {}).get("priceInCents"))
        limit = lenient_num((wallet.get("monthlyChargeLimit") or {}).get("priceInCents"))
        if left is not None or used is not None:
            credits = {"remaining": left / 1e8 if left is not None else None,
                       "used": used / 100 if used is not None else None,
                       "limit": limit / 100 if limit is not None
                                and wallet.get("monthlyChargeLimitEnabled") else None,
                       "unlimited": False}

    return {"status": "ok", "plan": plan, "account": None,
            "source": "kimi-oauth", "windows": windows, "credits": credits}


PROVIDERS = (("claude", fetch_claude), ("codex", fetch_codex), ("kimi", fetch_kimi))
MIN_INTERVALS = {"claude": CLAUDE_MIN_INTERVAL}


def fetch_all(providers=PROVIDERS):
    """Fetch independent providers concurrently, preserving output order."""
    selected = tuple(providers)
    if not selected:
        return {}
    result = {}
    with ThreadPoolExecutor(max_workers=len(selected), thread_name_prefix="usage") as pool:
        futures = [(name, pool.submit(fn)) for name, fn in selected]
        for name, future in futures:
            try:
                result[name] = future.result()
            except Exception as error:
                result[name] = err("parse", str(error))
    return result


def fetch_all_resilient(providers, state, now=None, min_intervals=None):
    """Fetch due providers and update persistent last-good/backoff state."""
    current = time.time() if now is None else now
    selected = tuple(providers)
    intervals = MIN_INTERVALS if min_intervals is None else min_intervals
    provider_state = state.setdefault("providers", {})
    if not isinstance(provider_state, dict):
        provider_state = {}
        state["providers"] = provider_state

    due = []
    skipped = {}
    for name, fetch in selected:
        entry = provider_state.get(name)
        if not isinstance(entry, dict):
            entry = {}
            provider_state[name] = entry
        next_attempt = entry.get("nextAttemptAt", 0)
        failures = entry.get("failures", 0)
        has_failures = isinstance(failures, int) and failures > 0
        if isinstance(next_attempt, (int, float)) and current < next_attempt:
            failure = entry.get("lastError") if has_failures else None
            cached = cached_provider(entry, current, failure, next_attempt)
            if cached is not None:
                skipped[name] = cached
                continue
            if isinstance(failure, dict):
                value = copy.deepcopy(failure)
                value["retryAt"] = int(next_attempt)
                skipped[name] = value
                continue
            if isinstance(entry.get("lastOk"), dict):
                skipped[name] = err(
                    "wait", "Waiting for the provider polling interval.",
                    retryAt=math.ceil(next_attempt))
                continue
        due.append((name, fetch))

    fetched = fetch_all(due)
    result = {}
    for name, _ in selected:
        if name in skipped:
            result[name] = skipped[name]
            continue

        value = fetched[name]
        if not isinstance(value, dict):
            value = err("parse", "Usage provider returned an invalid result.")
        entry = provider_state[name]
        minimum = intervals.get(name, 0)
        entry["lastAttemptAt"] = int(current)
        if value.get("status") == "ok":
            clean = copy.deepcopy(value)
            for key in ("observedAt", "stale", "staleKind", "staleMessage",
                        "retryAt"):
                clean.pop(key, None)
            entry.update({
                "lastOk": clean,
                "observedAt": int(current),
                "failures": 0,
                "nextAttemptAt": math.ceil(current + minimum),
            })
            entry.pop("lastError", None)
            value = copy.deepcopy(clean)
            value["observedAt"] = int(current)
            value["stale"] = False
            result[name] = value
            continue

        previous = entry.get("failures", 0)
        previous = previous if isinstance(previous, int) and previous >= 0 else 0
        failures = min(previous, 30) + 1
        retry_at = math.ceil(current + backoff_seconds(failures, minimum, value))
        failure = copy.deepcopy(value)
        entry.update({
            "failures": failures,
            "lastError": failure,
            "nextAttemptAt": retry_at,
        })
        cached = cached_provider(entry, current, failure, retry_at)
        if cached is not None:
            result[name] = cached
        else:
            failure["retryAt"] = retry_at
            result[name] = failure
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--refresh-claude",
        action="store_true",
        help="let the installed Claude CLI refresh expiring Claude credentials",
    )
    args = parser.parse_args()

    providers = (
        ("claude", lambda: fetch_claude(args.refresh_claude)),
        ("codex", fetch_codex),
        ("kimi", fetch_kimi),
    )
    path = usage_state_path()
    state = empty_state()
    lock = None
    lock_fd = None
    try:
        directory = os.path.dirname(path)
        os.makedirs(directory, mode=0o700, exist_ok=True)
        flags = os.O_CREAT | os.O_RDWR
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        lock_fd = os.open(path + ".lock", flags, 0o600)
        os.fchmod(lock_fd, 0o600)
        lock = os.fdopen(lock_fd, "r+")
        lock_fd = None
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        state = load_state(path)
    except OSError:
        if lock is not None:
            lock.close()
        elif lock_fd is not None:
            os.close(lock_fd)
        lock = None

    # Enabling refresh should immediately recover an auth failure left by the
    # disabled setting, but a failed enabled refresh still observes backoff.
    previous_refresh = state.get("claudeAutoRefresh")
    if args.refresh_claude and previous_refresh is not True:
        claude_state = state.get("providers", {}).get("claude", {})
        if not isinstance(claude_state, dict):
            claude_state = {}
            state["providers"]["claude"] = claude_state
        last_error = claude_state.get("lastError", {})
        if not isinstance(last_error, dict):
            last_error = {}
        if last_error.get("kind") in ("expired", "refresh"):
            claude_state["nextAttemptAt"] = 0
    state["claudeAutoRefresh"] = args.refresh_claude

    try:
        result = fetch_all_resilient(providers, state)
        if lock is not None:
            try:
                save_state(path, state)
            except (OSError, TypeError, ValueError):
                pass
    finally:
        if lock is not None:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
            lock.close()
    json.dump(result, sys.stdout)


if __name__ == "__main__":
    main()
