#!/usr/bin/env python3
"""Pair the Quickshell bar with a T3 Code server.

Usage:
    t3-pair.py 'https://host:port/pair#token=CODE'
    t3-pair.py https://host:port CODE

Exchanges the one-time pairing code for a ~30-day bearer token and
writes it to ~/.local/state/t3code-bar.json, which Common/T3Code.qml
watches — the bar picks the new credential up immediately.
"""

import json
import os
import sys
import urllib.parse
import urllib.request

STATE_PATH = os.path.expanduser("~/.local/state/t3code-bar.json")


def parse_args(argv):
    if len(argv) == 2:
        url = urllib.parse.urlparse(argv[1])
        code = (urllib.parse.parse_qs(url.fragment).get("token")
                or urllib.parse.parse_qs(url.query).get("token") or [None])[0]
        if not code:
            sys.exit("no token found in pairing URL")
        return f"{url.scheme}://{url.netloc}", code
    if len(argv) == 3:
        return argv[1].rstrip("/"), argv[2]
    sys.exit(__doc__.strip())


def main():
    base, code = parse_args(sys.argv)
    form = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
        "subject_token": code,
        "subject_token_type": "urn:t3:params:oauth:token-type:environment-bootstrap",
        "requested_token_type": "urn:ietf:params:oauth:token-type:access_token",
        "client_label": "Quickshell bar",
        "client_device_type": "desktop",
        "client_os": "linux",
    }).encode()
    req = urllib.request.Request(
        base + "/oauth/token", data=form, method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            result = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        sys.exit(f"pairing failed: HTTP {e.code} {e.read().decode()[:200]}")

    os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
    fd = os.open(STATE_PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump({
            "httpBaseUrl": base,
            "accessToken": result["access_token"],
            "expiresIn": result.get("expires_in"),
            "scope": result.get("scope"),
        }, f, indent=2)
    days = round((result.get("expires_in") or 0) / 86400)
    print(f"paired with {base} — token valid ~{days} days, saved to {STATE_PATH}")


if __name__ == "__main__":
    main()
