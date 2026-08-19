#!/usr/bin/env python3
"""Model-usage fetcher for the Quickshell menubar.

Reads the credential files the
provider CLIs (Claude Code, Codex CLI, Kimi Code) write locally and polls
each provider's own usage endpoint. Tokens are never refreshed here — the
CLIs own that; expired tokens surface as an error and recover once the user
runs the CLI again.

Prints one JSON object: {"claude": {...}, "codex": {...}, "kimi": {...}}
Each provider is {"status": "ok", ...} or {"status": "error", "kind": ...}.
"""

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

TIMEOUT = 20

FIVE_HOURS = 5 * 3600
SEVEN_DAYS = 7 * 24 * 3600


def home(*parts):
    return os.path.join(os.path.expanduser("~"), *parts)


def read_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def err(kind, message=""):
    return {"status": "error", "kind": kind, "message": message}


def http_get(url, headers):
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except Exception as e:  # DNS, timeout, TLS…
        return None, str(e)


def http_json(provider_cmd, url, headers):
    """Shared fetch + status handling. Returns (data, None) or (None, err)."""
    status, body = http_get(url, headers)
    if status is None:
        return None, err("network", body)
    if status == 429:
        return None, err("rate", "Rate limited by the usage endpoint.")
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


# ---------------------------------------------------------------- Claude

CLAUDE_PLANS = {"pro": "Claude Pro", "max": "Claude Max", "team": "Claude Team",
                "enterprise": "Claude Enterprise"}


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


def fetch_claude():
    cfg_dir = os.environ.get("CLAUDE_CONFIG_DIR") or home(".claude")
    path = os.path.join(cfg_dir, ".credentials.json")
    if not os.path.isfile(path):
        return err("nocreds", "claude")
    try:
        oauth = read_json(path)["claudeAiOauth"]
        token = oauth["accessToken"]
    except Exception:
        return err("nocreds", "claude")
    expires_at = oauth.get("expiresAt")
    if isinstance(expires_at, (int, float)) and expires_at <= time.time() * 1000:
        return err("expired", "claude")

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


def main():
    result = {}
    for name, fn in (("claude", fetch_claude), ("codex", fetch_codex), ("kimi", fetch_kimi)):
        try:
            result[name] = fn()
        except Exception as e:
            result[name] = err("parse", str(e))
    json.dump(result, sys.stdout)


if __name__ == "__main__":
    main()
