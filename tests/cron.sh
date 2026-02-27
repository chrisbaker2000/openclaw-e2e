# tests/cron.sh — Cron Delivery Health
# Validates cron job delivery config against docs-schema.json.

test_cron() {
    should_run "cron" || return 0
    has_container_access || return 0
    section "Cron Delivery Health (13 tests)"

    local cron_data
    cron_data=$(container_exec "cat $_PROC_CONFIG_DIR/cron/jobs.json") || cron_data=""

    if [ -z "$cron_data" ]; then
        skip "Cron jobs: not readable from container"
        return 0
    fi

    if [ ! -f "$DOCS_SCHEMA" ]; then
        fail "docs-schema.json not found at $DOCS_SCHEMA"
        return 0
    fi

    # 1. All jobs with delivery use 'to' (canonical field per docs)
    local bad_target_jobs
    bad_target_jobs=$(echo "$cron_data" | python3 -c "
import json, sys
data = json.load(sys.stdin)
bad = []
for j in data.get('jobs', []):
    d = j.get('delivery', {})
    if 'target' in d and 'to' not in d:
        bad.append(j.get('name', j.get('id', '?'))[:50])
print('|'.join(bad) if bad else 'ok')
" 2>/dev/null)
    if [ "$bad_target_jobs" = "ok" ]; then
        pass "Delivery config: all jobs use 'to' key (per docs)"
    else
        fail "Jobs use wrong 'target' instead of 'to': $(echo "$bad_target_jobs" | tr '|' ', ')"
    fi

    # 2. Delivery channels valid
    local invalid_channels
    invalid_channels=$(echo "$cron_data" | python3 -c "
import json, sys
data = json.load(sys.stdin)
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['cron']['delivery_fields']['channel_values'])
bad = []
for j in data.get('jobs', []):
    ch = j.get('delivery', {}).get('channel', '')
    if ch and ch not in valid:
        bad.append(f\"{j.get('name','?')[:40]}: {ch}\")
print('|'.join(bad) if bad else 'ok')
" 2>/dev/null)
    if [ "$invalid_channels" = "ok" ]; then
        pass "Delivery channels: all valid (per docs)"
    else
        fail "Invalid channels: $(echo "$invalid_channels" | tr '|' ', ')"
    fi

    # 3. Enabled jobs with delivery have a 'to' recipient
    local missing_to
    missing_to=$(echo "$cron_data" | python3 -c "
import json, sys
data = json.load(sys.stdin)
bad = []
for j in data.get('jobs', []):
    if not j.get('enabled', True):
        continue
    d = j.get('delivery', {})
    if d.get('channel') and not d.get('to'):
        bad.append(j.get('name', j.get('id', '?'))[:50])
print('|'.join(bad) if bad else 'ok')
" 2>/dev/null)
    if [ "$missing_to" = "ok" ]; then
        pass "Delivery recipients: all enabled jobs with channels have 'to'"
    else
        fail "Missing 'to': $(echo "$missing_to" | tr '|' ', ')"
    fi

    # 4. No enabled jobs stuck in error state
    local errored_jobs
    errored_jobs=$(echo "$cron_data" | python3 -c "
import json, sys
data = json.load(sys.stdin)
bad = []
for j in data.get('jobs', []):
    if not j.get('enabled', True):
        continue
    errs = j.get('state', {}).get('consecutiveErrors', 0)
    if errs and errs > 0:
        bad.append(f\"{j.get('name','?')[:40]}: {errs} errors\")
print('|'.join(bad) if bad else 'ok')
" 2>/dev/null)
    if [ "$errored_jobs" = "ok" ]; then
        pass "Job health: no enabled jobs with consecutive errors"
    else
        fail "Jobs in error state: $(echo "$errored_jobs" | tr '|' ', ')"
    fi

    # 5. Delivery modes valid (announce/webhook/none)
    local bad_modes
    bad_modes=$(echo "$cron_data" | python3 -c "
import json, sys
data = json.load(sys.stdin)
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['cron']['delivery_fields']['mode_values'])
bad = []
for j in data.get('jobs', []):
    m = j.get('delivery', {}).get('mode', '')
    if m and m not in valid:
        bad.append(f\"{j.get('name','?')[:40]}: mode={m}\")
print('|'.join(bad) if bad else 'ok')
" 2>/dev/null)
    if [ "$bad_modes" = "ok" ]; then
        pass "Delivery modes: all valid (per docs)"
    else
        fail "Invalid modes: $(echo "$bad_modes" | tr '|' ', ')"
    fi

    # 6. Session target + payload kind alignment
    local payload_mismatch
    payload_mismatch=$(echo "$cron_data" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
pk_map = schema['cron']['payload_kinds']
data = json.load(sys.stdin)
bad = []
for j in data.get('jobs', []):
    st = j.get('sessionTarget', '')
    pk = j.get('payload', {}).get('kind', '')
    if st and pk:
        expected = pk_map.get(st)
        if expected and pk != expected:
            bad.append(f\"{j.get('name','?')[:40]}: {st}+{pk}\")
print('|'.join(bad) if bad else 'ok')
" 2>/dev/null)
    if [ "$payload_mismatch" = "ok" ]; then
        pass "Session/payload: aligned (per docs)"
    else
        fail "Session/payload mismatch: $(echo "$payload_mismatch" | tr '|' ', ')"
    fi

    # 7. Schedule kinds valid (at/every/cron)
    local bad_schedules
    bad_schedules=$(echo "$cron_data" | python3 -c "
import json, sys
data = json.load(sys.stdin)
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['cron']['schedule_kinds'])
bad = []
for j in data.get('jobs', []):
    sk = j.get('schedule', {}).get('kind', '')
    if sk and sk not in valid:
        bad.append(f\"{j.get('name','?')[:40]}: kind={sk}\")
print('|'.join(bad) if bad else 'ok')
" 2>/dev/null)
    if [ "$bad_schedules" = "ok" ]; then
        pass "Schedule kinds: all valid (per docs)"
    else
        fail "Invalid schedule kinds: $(echo "$bad_schedules" | tr '|' ', ')"
    fi

    # 8. No legacy notify:true
    local notify_jobs
    notify_jobs=$(echo "$cron_data" | python3 -c "
import json, sys
data = json.load(sys.stdin)
bad = [j.get('name','?')[:50] for j in data.get('jobs', []) if j.get('notify') is True]
print('|'.join(bad) if bad else 'ok')
" 2>/dev/null)
    if [ "$notify_jobs" = "ok" ]; then
        pass "Legacy notify: no jobs using deprecated notify:true"
    else
        fail "Legacy notify:true: $(echo "$notify_jobs" | tr '|' ', ')"
    fi

    # 9. Schedule expressions have required fields
    local bad_exprs
    bad_exprs=$(echo "$cron_data" | python3 -c "
import json, sys
data = json.load(sys.stdin)
bad = []
for j in data.get('jobs', []):
    if not j.get('enabled', True):
        continue
    s = j.get('schedule', {})
    kind = s.get('kind', '')
    if kind == 'cron' and not s.get('expr'):
        bad.append(f\"{j.get('name','?')[:40]}: missing expr\")
    elif kind == 'every' and not s.get('everyMs'):
        bad.append(f\"{j.get('name','?')[:40]}: missing everyMs\")
    elif kind == 'at' and not s.get('at'):
        bad.append(f\"{j.get('name','?')[:40]}: missing at\")
print('|'.join(bad) if bad else 'ok')
" 2>/dev/null)
    if [ "$bad_exprs" = "ok" ]; then
        pass "Schedule expressions: all valid"
    else
        fail "Missing schedule fields: $(echo "$bad_exprs" | tr '|' ', ')"
    fi

    # 10. Model overrides use provider/model format
    local bad_models
    bad_models=$(echo "$cron_data" | python3 -c "
import json, sys
data = json.load(sys.stdin)
bad = []
for j in data.get('jobs', []):
    m = j.get('payload', {}).get('model', '') or j.get('model', '') or ''
    if not m:
        continue
    if '/' not in m or m.endswith('/default'):
        bad.append(f\"{j.get('name','?')[:40]}: model={m}\")
print('|'.join(bad) if bad else 'ok')
" 2>/dev/null)
    if [ "$bad_models" = "ok" ]; then
        pass "Model overrides: all use provider/model format"
    else
        fail "Invalid model overrides: $(echo "$bad_models" | tr '|' ', ')"
    fi

    # 11. Session targets valid (per docs: main, isolated)
    local bad_targets
    bad_targets=$(echo "$cron_data" | python3 -c "
import json, sys
data = json.load(sys.stdin)
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['cron']['session_targets'])
bad = []
for j in data.get('jobs', []):
    st = j.get('sessionTarget', '')
    if st and st not in valid:
        bad.append(f\"{j.get('name','?')[:40]}: {st}\")
print('|'.join(bad) if bad else 'ok')
" 2>/dev/null)
    if [ "$bad_targets" = "ok" ]; then
        pass "Session targets: all valid (per docs)"
    else
        fail "Invalid session targets: $(echo "$bad_targets" | tr '|' ', ')"
    fi

    # 12. Thinking levels in payload valid (per docs: off, minimal, low, medium, high, xhigh)
    local bad_thinking
    bad_thinking=$(echo "$cron_data" | python3 -c "
import json, sys
data = json.load(sys.stdin)
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['cron']['thinking_levels'])
bad = []
for j in data.get('jobs', []):
    level = j.get('payload', {}).get('thinking', '')
    if level and level not in valid:
        bad.append(f\"{j.get('name','?')[:40]}: thinking={level}\")
print('|'.join(bad) if bad else 'ok')
" 2>/dev/null)
    if [ "$bad_thinking" = "ok" ]; then
        pass "Payload thinking levels: all valid (per docs)"
    else
        fail "Invalid thinking levels: $(echo "$bad_thinking" | tr '|' ', ')"
    fi

    # 13. Wake modes valid (per docs: now, next-heartbeat)
    local bad_wake
    bad_wake=$(echo "$cron_data" | python3 -c "
import json, sys
data = json.load(sys.stdin)
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['cron']['wake_modes'])
bad = []
for j in data.get('jobs', []):
    wm = j.get('wakeMode', '')
    if wm and wm not in valid:
        bad.append(f\"{j.get('name','?')[:40]}: wakeMode={wm}\")
print('|'.join(bad) if bad else 'ok')
" 2>/dev/null)
    if [ "$bad_wake" = "ok" ]; then
        pass "Wake modes: all valid (per docs)"
    else
        fail "Invalid wake modes: $(echo "$bad_wake" | tr '|' ', ')"
    fi
}
