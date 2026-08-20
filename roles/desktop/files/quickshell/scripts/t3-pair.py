#!/usr/bin/env python3
"""Pair the Quickshell panel with a T3 Code server.

Usage:
    t3-pair.py --stdin
    t3-pair.py 'https://host:port/pair#token=CODE'
    t3-pair.py https://host:port CODE

Exchanges the one-time pairing code for a ~30-day bearer token and
writes it to ~/.local/state/t3code-bar.json, which Common/T3Code.qml
watches — the bar picks the new credential up immediately.

The Quickshell UI uses --stdin so the credential is not exposed in the
process argument list. The argv forms remain available for manual use.
"""

import json
import os
import sys
import tempfile
import urllib.parse
import urllib.error
import urllib.request

STATE_PATH = os.path.expanduser("~/.local/state/t3code-bar.json")


def normalize_base_url(raw):
    """Return an HTTP(S) origin suitable for the T3 OAuth endpoint."""
    url = urllib.parse.urlparse(raw.strip())
    if url.scheme not in {"http", "https", "ws", "wss"} or not url.netloc:
        raise ValueError("Pairing link must contain an http:// or https:// server URL.")
    if url.username is not None or url.password is not None:
        raise ValueError("Server URL must not contain embedded credentials.")
    scheme = {"ws": "http", "wss": "https"}.get(url.scheme, url.scheme)
    return urllib.parse.urlunparse((scheme, url.netloc, "", "", "", ""))


def parse_pairing_url(raw):
    """Resolve direct and app.t3.codes hosted pairing links."""
    url = urllib.parse.urlparse(raw.strip())
    query = urllib.parse.parse_qs(url.query)
    fragment = urllib.parse.parse_qs(url.fragment)
    code = (fragment.get("token") or query.get("token") or [None])[0]
    if not code or not code.strip():
        raise ValueError("That link does not contain a pairing token.")

    # A hosted pairing link points at app.t3.codes and carries the actual
    # backend in ?host=. Pair directly with that backend; the hosted site is a
    # client and does not proxy OAuth or WebSocket traffic.
    hosted_base = (query.get("host") or [None])[0]
    base = normalize_base_url(hosted_base if hosted_base else raw)
    return base, code.strip()


def parse_args(argv):
    if len(argv) == 2 and argv[1] == "--stdin":
        link = sys.stdin.readline()
        if not link:
            raise ValueError("No pairing link received.")
        return parse_pairing_url(link)
    if len(argv) == 2:
        return parse_pairing_url(argv[1])
    if len(argv) == 3:
        code = argv[2].strip()
        if not code:
            raise ValueError("No pairing code received.")
        return normalize_base_url(argv[1]), code
    raise ValueError(__doc__.strip())


def save_state(base, result):
    if not isinstance(result, dict):
        raise ValueError("Pairing server returned an unreadable response.")
    token = result.get("access_token")
    if not isinstance(token, str) or not token:
        raise ValueError("Pairing server returned no access token.")

    state_dir = os.path.dirname(STATE_PATH)
    os.makedirs(state_dir, exist_ok=True)
    fd, temporary_path = tempfile.mkstemp(prefix=".t3code-bar-", dir=state_dir)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w") as state_file:
            json.dump({
                "httpBaseUrl": base,
                "accessToken": token,
                "expiresIn": result.get("expires_in"),
                "scope": result.get("scope"),
            }, state_file, indent=2)
            state_file.write("\n")
        os.replace(temporary_path, STATE_PATH)
    except BaseException:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.unlink(temporary_path)
        except FileNotFoundError:
            pass
        raise


def main():
    try:
        base, code = parse_args(sys.argv)
    except ValueError as error:
        sys.exit(str(error))

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
    except urllib.error.HTTPError as error:
        if error.code in {401, 403}:
            sys.exit("Pairing link is invalid, expired, or already used.")
        sys.exit(f"Pairing server returned HTTP {error.code}.")
    except urllib.error.URLError as error:
        reason = str(error.reason).strip()
        sys.exit("Could not reach the T3 server"
                 + (f": {reason}." if reason else "."))
    except TimeoutError:
        sys.exit("The T3 server did not respond in time.")
    except (UnicodeDecodeError, json.JSONDecodeError):
        sys.exit("Pairing server returned an unreadable response.")

    try:
        save_state(base, result)
    except (KeyError, TypeError, ValueError) as error:
        sys.exit(str(error))

    days = round((result.get("expires_in") or 0) / 86400)
    print(f"paired with {base} — token valid ~{days} days, saved to {STATE_PATH}")


if __name__ == "__main__":
    main()
