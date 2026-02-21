# tests/channels.sh — Channel Connectivity (Slack, Discord)
# Runs when OPENCLAW_SLACK_ENABLED or OPENCLAW_DISCORD_ENABLED is true.

test_channels() {
    should_run "channels" || return 0
    has_container_access || return 0

    local slack_enabled="${OPENCLAW_SLACK_ENABLED:-false}"
    local discord_enabled="${OPENCLAW_DISCORD_ENABLED:-false}"

    if [ "$slack_enabled" != "true" ] && [ "$discord_enabled" != "true" ]; then
        return 0
    fi

    local test_count=0
    [ "$slack_enabled" = "true" ] && test_count=$((test_count + 3))
    [ "$discord_enabled" = "true" ] && test_count=$((test_count + 2))
    section "Channels ($test_count tests)"

    if [ -z "$GATEWAY_LOGS" ]; then
        skip "Channels: logs not available"
        return 0
    fi

    # ─── Slack ─────────────────────────────────────────────────────
    if [ "$slack_enabled" = "true" ]; then
        # 1. Socket mode connected
        if echo "$GATEWAY_LOGS" | grep -qi "socket mode connected\|slack.*connected\|bolt.*connected"; then
            pass "Slack: socket mode connected"
        else
            fail "Slack: socket mode not connected"
        fi

        # 2. No Slack auth errors
        if echo "$GATEWAY_LOGS" | grep -qi "invalid_auth\|slack.*auth.*fail\|slack.*token.*invalid"; then
            fail "Slack: authentication errors in logs"
        else
            pass "Slack: no authentication errors"
        fi

        # 3. Slack dmPolicy valid (if docs-schema available)
        if [ -f "$DOCS_SCHEMA" ] && [ -n "$GATEWAY_CONFIG" ]; then
            local slack_dm_check
            slack_dm_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['slack']['dm_policies'])
config = json.load(sys.stdin)
slack = config.get('channels', {}).get('slack', {})
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
    fi

    # ─── Discord ───────────────────────────────────────────────────
    if [ "$discord_enabled" = "true" ]; then
        # 1. Discord logged in
        if echo "$GATEWAY_LOGS" | grep -qi "logged in.*discord\|discord.*ready\|discord.*connected"; then
            pass "Discord: logged in"
        else
            fail "Discord: not logged in"
        fi

        # 2. Discord dmPolicy valid
        if [ -f "$DOCS_SCHEMA" ] && [ -n "$GATEWAY_CONFIG" ]; then
            local discord_dm_check
            discord_dm_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['discord']['dm_policies'])
config = json.load(sys.stdin)
discord = config.get('channels', {}).get('discord', {})
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
    fi
}
