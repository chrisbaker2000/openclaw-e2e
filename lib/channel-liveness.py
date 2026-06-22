#!/usr/bin/env python3
"""Live channel-connectivity probe for the e2e channels section (LAB-273).

Reads the gateway config JSON on stdin, extracts the bot credential for the
requested channel, and performs a single live identity call to confirm the
channel is actually connected RIGHT NOW (not merely that a connect line once
scrolled through a trimmed log buffer).

Usage:
    echo "$GATEWAY_CONFIG" | python3 lib/channel-liveness.py slack
    echo "$GATEWAY_CONFIG" | python3 lib/channel-liveness.py discord

Prints exactly one of:
    ok    — credential valid and provider reachable
    bad   — credential rejected (invalid / revoked)
    ""    — undetermined (no credential, network error, or timeout)

The credential is read straight from config and handed to curl; it is never
echoed, logged, or returned. Every network call is bounded by connect/total
timeouts so an unavailable endpoint degrades to "" and the caller falls back
to log-based evidence.
"""
import json
import subprocess
import sys

# channel -> (config field names in priority order, curl auth header prefix, identity URL)
PROBES = {
    "slack": (("botToken", "token"), "Authorization: Bearer ", "https://slack.com/api/auth.test"),
    "discord": (("token", "botToken"), "Authorization: Bot ", "https://discord.com/api/v10/users/@me"),
}


def _credential(config: dict, channel: str, fields: tuple) -> str:
    section = config.get("channels", {}).get(channel, config.get(channel, {}))
    for field in fields:
        value = section.get(field)
        if value:
            return value
    return ""


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in PROBES:
        print("")
        return 0
    channel = sys.argv[1]
    fields, auth_prefix, url = PROBES[channel]

    try:
        config = json.load(sys.stdin)
    except Exception:
        print("")
        return 0

    cred = _credential(config, channel, fields)
    if not cred:
        print("")
        return 0

    try:
        if channel == "slack":
            # auth.test returns 200 with {"ok": true|false}
            out = subprocess.run(
                ["curl", "-s", "--connect-timeout", "5", "--max-time", "10",
                 "-H", auth_prefix + cred, url],
                capture_output=True, text=True, timeout=15,
            ).stdout
            print("ok" if json.loads(out).get("ok") else "bad")
        else:  # discord — distinguish by HTTP status
            code = subprocess.run(
                ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                 "--connect-timeout", "5", "--max-time", "10",
                 "-H", auth_prefix + cred, url],
                capture_output=True, text=True, timeout=15,
            ).stdout.strip()
            print("ok" if code == "200" else ("bad" if code in ("401", "403") else ""))
    except Exception:
        print("")
    return 0


if __name__ == "__main__":
    sys.exit(main())
