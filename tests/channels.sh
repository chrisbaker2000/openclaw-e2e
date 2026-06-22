# tests/channels.sh — Channel Connectivity & Config (Slack, Discord)
# Runs when OPENCLAW_SLACK_ENABLED or OPENCLAW_DISCORD_ENABLED is true.

# Channel-credential presence helper: reads the bot credential for a channel
# out of the gateway config JSON (on stdin) and prints "yes"/"no". Keeps the
# raw credential out of the calling shell scope.
_channel_has_cred() {
    local channel="$1"
    python3 -c "
import json, sys
d = json.load(sys.stdin)
c = d.get('channels', {}).get('$channel', d.get('$channel', {}))
print('yes' if c.get('botToken') or c.get('token') else 'no')
" 2>/dev/null
}

# Live liveness probes. Delegate to lib/channel-liveness.py, which reads the
# gateway config JSON on stdin, extracts the channel's bot credential, and
# performs a single bounded identity call (Slack auth.test / Discord
# /users/@me) — the credential stays inside that script and is never echoed
# into the test shell. Returns: "ok" (alive), "bad" (rejected), or ""
# (undetermined — no credential / network / timeout; caller falls back to logs).
# Same approach as the Slack auth.test in tests/local/integrations.sh.
_slack_liveness() {
    python3 "$SCRIPT_DIR/lib/channel-liveness.py" slack 2>/dev/null
}

_discord_liveness() {
    python3 "$SCRIPT_DIR/lib/channel-liveness.py" discord 2>/dev/null
}

test_channels() {
    should_run "channels" || return 0
    has_container_access || return 0

    local slack_enabled="${OPENCLAW_SLACK_ENABLED:-false}"
    local discord_enabled="${OPENCLAW_DISCORD_ENABLED:-false}"

    if [ "$slack_enabled" != "true" ] && [ "$discord_enabled" != "true" ]; then
        return 0
    fi

    local test_count=0
    [ "$slack_enabled" = "true" ] && test_count=$((test_count + 6))
    [ "$discord_enabled" = "true" ] && test_count=$((test_count + 5))
    section "Channels ($test_count tests)"

    if [ -z "$GATEWAY_LOGS" ]; then
        skip "Channels: logs not available"
        return 0
    fi

    # ─── Slack ─────────────────────────────────────────────────────
    if [ "$slack_enabled" = "true" ]; then
        # 1. Slack connected — PRIMARY signal is a live Slack auth.test (proves
        #    the credential is valid and Slack is reachable RIGHT NOW, not just
        #    that a connect line once appeared in a log buffer prefetch trims to
        #    the last startup window). Order: live auth.test → recent connect log
        #    → credential-present "configured" (an explicitly weaker assertion,
        #    NOT "connected"). The probe is network-gated and degrades to "".
        local slack_live slack_cfg
        slack_live=$(echo "$GATEWAY_CONFIG" | _slack_liveness)
        slack_cfg=$(echo "$GATEWAY_CONFIG" | _channel_has_cred slack)
        if [ "$slack_live" = "ok" ]; then
            pass "Slack: connected (live auth.test ok)"
        elif [ "$slack_live" = "bad" ]; then
            fail "Slack: auth.test failed — credential invalid or revoked"
        elif echo "$GATEWAY_LOGS" | grep -qi "socket mode connected\|slack.*connected\|bolt.*connected"; then
            pass "Slack: connected (socket mode log)"
        elif [ "$slack_cfg" = "yes" ]; then
            pass "Slack: configured (credential present; liveness unconfirmed)"
        else
            fail "Slack: not connected or configured"
        fi

        # 2. No Slack auth errors
        if echo "$GATEWAY_LOGS" | grep -qi "invalid_auth\|slack.*auth.*fail\|slack.*token.*invalid"; then
            fail "Slack: authentication errors in logs"
        else
            pass "Slack: no authentication errors"
        fi

        # 3. Slack dmPolicy valid (per docs: pairing, allowlist, open, disabled)
        if [ -f "$DOCS_SCHEMA" ] && [ -n "$GATEWAY_CONFIG" ]; then
            local slack_dm_check
            slack_dm_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['slack']['dm_policies'])
config = json.load(sys.stdin)
slack = config.get('channels', {}).get('slack', config.get('slack', {}))
policy = slack.get('dmPolicy', '') or slack.get('dm', {}).get('policy', '')
if not policy or policy in valid:
    print('ok')
else:
    print(f'invalid: {policy}')
" 2>/dev/null)
            if [ "$slack_dm_check" = "ok" ]; then
                pass "Slack dmPolicy: valid"
            else
                fail "Slack dmPolicy $slack_dm_check"
            fi
        else
            skip "Slack dmPolicy: schema or config not available"
        fi

        # 4. Slack mode valid (per docs: socket, http)
        if [ -f "$DOCS_SCHEMA" ] && [ -n "$GATEWAY_CONFIG" ]; then
            local slack_mode_check
            slack_mode_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['slack']['modes'])
config = json.load(sys.stdin)
slack = config.get('channels', {}).get('slack', config.get('slack', {}))
mode = slack.get('mode', '')
if not mode or mode in valid:
    print('ok')
else:
    print(f'invalid: {mode}')
" 2>/dev/null)
            if [ "$slack_mode_check" = "ok" ]; then
                pass "Slack mode: valid"
            else
                fail "Slack mode $slack_mode_check"
            fi
        else
            skip "Slack mode: schema or config not available"
        fi

        # 5. Slack replyToMode valid (per docs: off, first, all)
        if [ -f "$DOCS_SCHEMA" ] && [ -n "$GATEWAY_CONFIG" ]; then
            local slack_reply_check
            slack_reply_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['slack']['reply_to_modes'])
config = json.load(sys.stdin)
slack = config.get('channels', {}).get('slack', config.get('slack', {}))
mode = slack.get('replyToMode', '')
if not mode or mode in valid:
    print('ok')
else:
    print(f'invalid: {mode}')
" 2>/dev/null)
            if [ "$slack_reply_check" = "ok" ]; then
                pass "Slack replyToMode: valid"
            else
                fail "Slack replyToMode $slack_reply_check"
            fi
        else
            skip "Slack replyToMode: schema or config not available"
        fi

        # 6. Slack groupPolicy valid (per docs: open, allowlist, disabled)
        if [ -f "$DOCS_SCHEMA" ] && [ -n "$GATEWAY_CONFIG" ]; then
            local slack_group_check
            slack_group_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['slack']['group_policies'])
config = json.load(sys.stdin)
slack = config.get('channels', {}).get('slack', config.get('slack', {}))
policy = slack.get('groupPolicy', '') or slack.get('group', {}).get('policy', '')
if not policy or policy in valid:
    print('ok')
else:
    print(f'invalid: {policy}')
" 2>/dev/null)
            if [ "$slack_group_check" = "ok" ]; then
                pass "Slack groupPolicy: valid"
            else
                fail "Slack groupPolicy $slack_group_check"
            fi
        else
            skip "Slack groupPolicy: schema or config not available"
        fi
    fi

    # ─── Discord ───────────────────────────────────────────────────
    if [ "$discord_enabled" = "true" ]; then
        # 1. Discord connected — PRIMARY signal is a live GET /users/@me with
        #    the bot credential (proves the credential is valid and Discord is
        #    reachable now). Order: live /users/@me → recent ready/connected log
        #    → credential-present "configured" (explicitly weaker, NOT
        #    "connected"). The probe is network-gated and degrades to "".
        local discord_live discord_cfg
        discord_live=$(echo "$GATEWAY_CONFIG" | _discord_liveness)
        discord_cfg=$(echo "$GATEWAY_CONFIG" | _channel_has_cred discord)
        if [ "$discord_live" = "ok" ]; then
            pass "Discord: connected (live /users/@me ok)"
        elif [ "$discord_live" = "bad" ]; then
            fail "Discord: /users/@me failed — credential invalid or revoked"
        elif echo "$GATEWAY_LOGS" | grep -qi "logged in.*discord\|discord.*ready\|discord.*connected"; then
            pass "Discord: connected (ready log)"
        elif [ "$discord_cfg" = "yes" ]; then
            pass "Discord: configured (credential present; liveness unconfirmed)"
        else
            fail "Discord: not connected or configured"
        fi

        # 2. Discord dmPolicy valid (per docs: pairing, allowlist, open, disabled)
        if [ -f "$DOCS_SCHEMA" ] && [ -n "$GATEWAY_CONFIG" ]; then
            local discord_dm_check
            discord_dm_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['discord']['dm_policies'])
config = json.load(sys.stdin)
discord = config.get('channels', {}).get('discord', config.get('discord', {}))
policy = discord.get('dmPolicy', '') or discord.get('dm', {}).get('policy', '')
if not policy or policy in valid:
    print('ok')
else:
    print(f'invalid: {policy}')
" 2>/dev/null)
            if [ "$discord_dm_check" = "ok" ]; then
                pass "Discord dmPolicy: valid"
            else
                fail "Discord dmPolicy $discord_dm_check"
            fi
        else
            skip "Discord dmPolicy: schema or config not available"
        fi

        # 3. Discord streamMode valid (per docs: off, partial, block)
        if [ -f "$DOCS_SCHEMA" ] && [ -n "$GATEWAY_CONFIG" ]; then
            local discord_stream_check
            discord_stream_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['channels']['stream_modes'])
config = json.load(sys.stdin)
discord = config.get('channels', {}).get('discord', config.get('discord', {}))
mode = discord.get('streamMode', '')
if not mode or mode in valid:
    print('ok')
else:
    print(f'invalid: {mode}')
" 2>/dev/null)
            if [ "$discord_stream_check" = "ok" ]; then
                pass "Discord streamMode: valid"
            else
                fail "Discord streamMode $discord_stream_check"
            fi
        else
            skip "Discord streamMode: schema or config not available"
        fi

        # 4. Discord groupPolicy valid (per docs: open, allowlist, disabled)
        if [ -f "$DOCS_SCHEMA" ] && [ -n "$GATEWAY_CONFIG" ]; then
            local discord_group_check
            discord_group_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['discord']['group_policies'])
config = json.load(sys.stdin)
discord = config.get('channels', {}).get('discord', config.get('discord', {}))
policy = discord.get('groupPolicy', '') or discord.get('group', {}).get('policy', '')
if not policy or policy in valid:
    print('ok')
else:
    print(f'invalid: {policy}')
" 2>/dev/null)
            if [ "$discord_group_check" = "ok" ]; then
                pass "Discord groupPolicy: valid"
            else
                fail "Discord groupPolicy $discord_group_check"
            fi
        else
            skip "Discord groupPolicy: schema or config not available"
        fi

        # 5. Discord replyToMode valid (per docs: off, first, all)
        if [ -f "$DOCS_SCHEMA" ] && [ -n "$GATEWAY_CONFIG" ]; then
            local discord_reply_check
            discord_reply_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['channels']['reply_to_modes'])
config = json.load(sys.stdin)
discord = config.get('channels', {}).get('discord', config.get('discord', {}))
mode = discord.get('replyToMode', '')
if not mode or mode in valid:
    print('ok')
else:
    print(f'invalid: {mode}')
" 2>/dev/null)
            if [ "$discord_reply_check" = "ok" ]; then
                pass "Discord replyToMode: valid"
            else
                fail "Discord replyToMode $discord_reply_check"
            fi
        else
            skip "Discord replyToMode: schema or config not available"
        fi
    fi
}
