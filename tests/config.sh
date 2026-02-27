# tests/config.sh — Config Schema Compliance
# Runs when container access is available. Validates config values
# against docs-schema.json.

test_config() {
    should_run "config" || return 0
    has_container_access || return 0
    section "Config Schema Compliance (22 tests)"

    if [ -z "$GATEWAY_CONFIG" ]; then
        fail "Gateway config: not readable"
        return 0
    fi

    if [ ! -f "$DOCS_SCHEMA" ]; then
        fail "docs-schema.json not found at $DOCS_SCHEMA"
        return 0
    fi

    # 1. Shared config has required top-level sections
    local shared_config
    shared_config=$(container_exec "cat $_PROC_CONFIG_DIR/workspace/shared-config.json") || shared_config=""
    if [ -n "$shared_config" ]; then
        local missing_sections
        missing_sections=$(echo "$shared_config" | python3 -c "
import json, sys
d = json.load(sys.stdin)
required = {'agents', 'models', 'session', 'skills', 'tools'}
missing = required - set(d.keys())
print(','.join(sorted(missing)) if missing else 'ok')
" 2>/dev/null)
        if [ "$missing_sections" = "ok" ]; then
            pass "Shared config: all required sections present"
        else
            fail "Shared config: missing sections: $missing_sections"
        fi
    else
        skip "Shared config: not readable"
    fi

    # 2. Primary model uses provider/model format
    if [ -n "$shared_config" ]; then
        local primary_format
        primary_format=$(echo "$shared_config" | python3 -c "
import json, sys, re
d = json.load(sys.stdin)
primary = d.get('agents', {}).get('defaults', {}).get('model', '')
if isinstance(primary, dict):
    primary = primary.get('primary', '')
schema = json.load(open('$DOCS_SCHEMA'))
pattern = schema['models']['ref_format']
if not primary:
    print('ok')  # no primary set, defaults apply
elif re.match(pattern, primary):
    print('ok')
else:
    print(primary)
" 2>/dev/null)
        if [ "$primary_format" = "ok" ]; then
            pass "Primary model format: valid provider/model pattern"
        else
            fail "Primary model format invalid: '$primary_format'"
        fi
    else
        skip "Primary model format: shared config not readable"
    fi

    # 3. Custom providers have required fields (baseUrl + api)
    if [ -n "$shared_config" ]; then
        local incomplete_providers
        incomplete_providers=$(echo "$shared_config" | python3 -c "
import json, sys
d = json.load(sys.stdin)
schema = json.load(open('$DOCS_SCHEMA'))
required = schema['models']['custom_provider_required_fields']
providers = d.get('models', {}).get('providers', {})
bad = []
for name, cfg in providers.items():
    missing = [f for f in required if f not in cfg]
    if missing:
        bad.append(f'{name}: missing {missing}')
print('|'.join(bad) if bad else 'ok')
" 2>/dev/null)
        if [ "$incomplete_providers" = "ok" ]; then
            pass "Custom providers: all have required fields (baseUrl + api)"
        else
            fail "Incomplete providers: $(echo "$incomplete_providers" | tr '|' ', ')"
        fi
    else
        skip "Custom providers: shared config not readable"
    fi

    # 4. Provider API types valid
    if [ -n "$shared_config" ]; then
        local bad_api_types
        bad_api_types=$(echo "$shared_config" | python3 -c "
import json, sys
d = json.load(sys.stdin)
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['models']['api_types'])
providers = d.get('models', {}).get('providers', {})
bad = []
for name, cfg in providers.items():
    api = cfg.get('api', '')
    if api and api not in valid:
        bad.append(f'{name}: api={api}')
print('|'.join(bad) if bad else 'ok')
" 2>/dev/null)
        if [ "$bad_api_types" = "ok" ]; then
            pass "Provider API types: all valid"
        else
            fail "Invalid API types: $(echo "$bad_api_types" | tr '|' ', ')"
        fi
    else
        skip "Provider API types: shared config not readable"
    fi

    # 5. Gateway auth mode valid
    local auth_check
    auth_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['gateway']['auth_modes'])
config = json.load(sys.stdin)
mode = config.get('gateway', {}).get('auth', {}).get('mode', '')
if not mode:
    print('ok')
elif mode in valid:
    print('ok')
else:
    print(f'invalid: {mode}')
" 2>/dev/null)
    if [ "$auth_check" = "ok" ]; then
        pass "Gateway auth mode: valid"
    else
        fail "Gateway auth mode $auth_check"
    fi

    # 6. Gateway bind mode valid
    local bind_check
    bind_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['gateway']['bind_modes'])
config = json.load(sys.stdin)
bind = config.get('gateway', {}).get('bind', '')
if not bind:
    print('ok')
elif bind in valid:
    print('ok')
else:
    print(f'invalid: {bind}')
" 2>/dev/null)
    if [ "$bind_check" = "ok" ]; then
        pass "Gateway bind mode: valid"
    else
        fail "Gateway bind mode $bind_check"
    fi

    # 7. Gateway reload mode valid
    local reload_check
    reload_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['gateway']['reload_modes'])
config = json.load(sys.stdin)
mode = config.get('gateway', {}).get('reload', {}).get('mode', '')
if not mode:
    print('ok')
elif mode in valid:
    print('ok')
else:
    print(f'invalid: {mode}')
" 2>/dev/null)
    if [ "$reload_check" = "ok" ]; then
        pass "Gateway reload mode: valid"
    else
        fail "Gateway reload mode $reload_check"
    fi

    # 8. Session dmScope valid
    local dmscope_check
    dmscope_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['session']['dm_scopes'])
config = json.load(sys.stdin)
scope = config.get('session', {}).get('dmScope', '')
if not scope:
    print('ok')
elif scope in valid:
    print('ok')
else:
    print(f'invalid: {scope}')
" 2>/dev/null)
    if [ "$dmscope_check" = "ok" ]; then
        pass "Session dmScope: valid"
    else
        fail "Session dmScope $dmscope_check"
    fi

    # 9. No 'provider/default' model refs
    if [ -n "$shared_config" ]; then
        local default_models
        default_models=$(echo "$shared_config" | python3 -c "
import json, sys, re
d = json.load(sys.stdin)
text = json.dumps(d)
matches = re.findall(r'[a-z-]+/default', text)
print('|'.join(set(matches)) if matches else 'ok')
" 2>/dev/null)
        if [ "$default_models" = "ok" ]; then
            pass "Model refs: no 'provider/default' patterns"
        else
            fail "Invalid 'default' model refs: $(echo "$default_models" | tr '|' ', ')"
        fi
    else
        skip "Model refs: shared config not readable"
    fi

    # 10. All fallback models have known providers
    if [ -n "$shared_config" ]; then
        local orphan_models
        orphan_models=$(echo "$shared_config" | python3 -c "
import json, sys
d = json.load(sys.stdin)
schema = json.load(open('$DOCS_SCHEMA'))
builtins = set(schema['models']['builtin_providers'])
custom = set(d.get('models', {}).get('providers', {}).keys())
known = builtins | custom
model_cfg = d.get('agents', {}).get('defaults', {}).get('model', {})
fallbacks = model_cfg.get('fallbacks', []) if isinstance(model_cfg, dict) else []
bad = []
for fb in fallbacks:
    if '/' in fb:
        provider = fb.split('/')[0]
        if provider not in known:
            bad.append(fb)
print('|'.join(bad) if bad else 'ok')
" 2>/dev/null)
        if [ "$orphan_models" = "ok" ]; then
            pass "Fallback providers: all models have known providers"
        else
            fail "Orphan fallback models: $(echo "$orphan_models" | tr '|' ', ')"
        fi
    else
        skip "Fallback providers: shared config not readable"
    fi

    # 11. Session reset mode valid (per docs: daily, idle)
    if [ -n "$shared_config" ]; then
        local reset_check
        reset_check=$(echo "$shared_config" | python3 -c "
import json, sys
d = json.load(sys.stdin)
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['session']['reset_modes'])
mode = d.get('session', {}).get('reset', {}).get('mode', '')
if not mode:
    print('ok')
elif mode in valid:
    print('ok')
else:
    print(f'invalid: {mode}')
" 2>/dev/null)
        if [ "$reset_check" = "ok" ]; then
            pass "Session reset mode: valid"
        else
            fail "Session reset mode $reset_check"
        fi
    else
        skip "Session reset mode: shared config not readable"
    fi

    # 12. Messages humanDelay mode valid (per docs: off, natural, custom)
    local delay_check
    delay_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['messages']['human_delay_modes'])
config = json.load(sys.stdin)
mode = config.get('humanDelay', {}).get('mode', '') or config.get('messages', {}).get('humanDelay', {}).get('mode', '')
if not mode:
    print('ok')
elif mode in valid:
    print('ok')
else:
    print(f'invalid: {mode}')
" 2>/dev/null)
    if [ "$delay_check" = "ok" ]; then
        pass "Messages humanDelay mode: valid"
    else
        fail "Messages humanDelay mode $delay_check"
    fi

    # 13. Messages queue mode valid (per docs: steer, followup, collect, etc.)
    if [ -n "$shared_config" ]; then
        local queue_check
        queue_check=$(echo "$shared_config" | python3 -c "
import json, sys
d = json.load(sys.stdin)
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['messages']['queue_modes'])
mode = d.get('messages', {}).get('queue', {}).get('mode', '')
if not mode:
    print('ok')
elif mode in valid:
    print('ok')
else:
    print(f'invalid: {mode}')
" 2>/dev/null)
        if [ "$queue_check" = "ok" ]; then
            pass "Messages queue mode: valid"
        else
            fail "Messages queue mode $queue_check"
        fi
    else
        skip "Messages queue mode: shared config not readable"
    fi

    # 14. Messages typingMode valid (per docs: never, instant, thinking, message)
    if [ -n "$shared_config" ]; then
        local typing_check
        typing_check=$(echo "$shared_config" | python3 -c "
import json, sys
d = json.load(sys.stdin)
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['messages']['typing_modes'])
mode = d.get('messages', {}).get('typingMode', '')
if not mode:
    print('ok')
elif mode in valid:
    print('ok')
else:
    print(f'invalid: {mode}')
" 2>/dev/null)
        if [ "$typing_check" = "ok" ]; then
            pass "Messages typingMode: valid"
        else
            fail "Messages typingMode $typing_check"
        fi
    else
        skip "Messages typingMode: shared config not readable"
    fi

    # 15. Tailscale mode valid (per docs: off, serve, funnel)
    local ts_check
    ts_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['gateway']['tailscale_modes'])
config = json.load(sys.stdin)
mode = config.get('gateway', {}).get('tailscale', {}).get('mode', '')
if not mode:
    print('ok')
elif mode in valid:
    print('ok')
else:
    print(f'invalid: {mode}')
" 2>/dev/null)
    if [ "$ts_check" = "ok" ]; then
        pass "Gateway tailscale mode: valid"
    else
        fail "Gateway tailscale mode $ts_check"
    fi

    # 16. Funnel requires password auth (per docs: cross-validation)
    local funnel_check
    funnel_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
config = json.load(sys.stdin)
ts_mode = config.get('gateway', {}).get('tailscale', {}).get('mode', '')
auth_mode = config.get('gateway', {}).get('auth', {}).get('mode', '')
if ts_mode == 'funnel' and auth_mode != schema['gateway']['funnel_requires_auth']:
    print(f'funnel requires password auth, got: {auth_mode}')
else:
    print('ok')
" 2>/dev/null)
    if [ "$funnel_check" = "ok" ]; then
        pass "Funnel auth cross-check: valid"
    else
        fail "Funnel auth: $funnel_check"
    fi

    # 17. Logging console style valid (per docs: pretty, compact, json)
    local log_style_check
    log_style_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['logging']['console_styles'])
config = json.load(sys.stdin)
style = config.get('logging', {}).get('consoleStyle', '')
if not style:
    print('ok')
elif style in valid:
    print('ok')
else:
    print(f'invalid: {style}')
" 2>/dev/null)
    if [ "$log_style_check" = "ok" ]; then
        pass "Logging console style: valid"
    else
        fail "Logging console style $log_style_check"
    fi

    # 18. Logging redactSensitive valid (per docs: off, tools, all)
    local redact_check
    redact_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['logging']['redact_modes'])
config = json.load(sys.stdin)
mode = config.get('logging', {}).get('redactSensitive', '')
if not mode:
    print('ok')
elif mode in valid:
    print('ok')
else:
    print(f'invalid: {mode}')
" 2>/dev/null)
    if [ "$redact_check" = "ok" ]; then
        pass "Logging redactSensitive: valid"
    else
        fail "Logging redactSensitive $redact_check"
    fi

    # 19. Agent thinking level valid (per docs: off, minimal, low, medium, high, xhigh)
    if [ -n "$shared_config" ]; then
        local thinking_check
        thinking_check=$(echo "$shared_config" | python3 -c "
import json, sys
d = json.load(sys.stdin)
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['agents']['thinking_levels'])
level = d.get('agents', {}).get('defaults', {}).get('thinkingDefault', '')
if not level:
    print('ok')
elif level in valid:
    print('ok')
else:
    print(f'invalid: {level}')
" 2>/dev/null)
        if [ "$thinking_check" = "ok" ]; then
            pass "Agent thinking level: valid"
        else
            fail "Agent thinking level $thinking_check"
        fi
    else
        skip "Agent thinking level: shared config not readable"
    fi

    # 20. Tool sessions visibility valid (per docs: self, tree, agent, all)
    if [ -n "$shared_config" ]; then
        local vis_check
        vis_check=$(echo "$shared_config" | python3 -c "
import json, sys
d = json.load(sys.stdin)
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['tools']['visibility_modes'])
mode = d.get('tools', {}).get('sessions', {}).get('visibility', '')
if not mode:
    print('ok')
elif mode in valid:
    print('ok')
else:
    print(f'invalid: {mode}')
" 2>/dev/null)
        if [ "$vis_check" = "ok" ]; then
            pass "Tool sessions visibility: valid"
        else
            fail "Tool sessions visibility $vis_check"
        fi
    else
        skip "Tool sessions visibility: shared config not readable"
    fi

    # 21. Session maintenance mode valid (per docs: warn, enforce)
    if [ -n "$shared_config" ]; then
        local maint_check
        maint_check=$(echo "$shared_config" | python3 -c "
import json, sys
d = json.load(sys.stdin)
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['session']['maintenance_modes'])
mode = d.get('session', {}).get('maintenance', {}).get('mode', '')
if not mode:
    print('ok')
elif mode in valid:
    print('ok')
else:
    print(f'invalid: {mode}')
" 2>/dev/null)
        if [ "$maint_check" = "ok" ]; then
            pass "Session maintenance mode: valid"
        else
            fail "Session maintenance mode $maint_check"
        fi
    else
        skip "Session maintenance mode: shared config not readable"
    fi

    # 22. Cron delivery uses canonical "to" field (not "target")
    if has_container_access; then
        local cron_field_check
        cron_field_check=$(container_exec "python3 -c '
import json, os
path = \"$_PROC_CONFIG_DIR/cron/jobs.json\"
if not os.path.exists(path):
    print(\"no-cron\")
else:
    with open(path) as f:
        jobs = json.load(f)
    if not isinstance(jobs, list):
        jobs = jobs.get(\"jobs\", [])
    bad = []
    for j in jobs:
        delivery = j.get(\"delivery\", {})
        if \"target\" in delivery and \"to\" not in delivery:
            bad.append(j.get(\"name\", \"unnamed\"))
    print(\"|\".join(bad) if bad else \"ok\")
'" | tr -d '\r\n')
        if [ "$cron_field_check" = "no-cron" ]; then
            skip "Cron delivery field: no jobs.json found"
        elif [ "$cron_field_check" = "ok" ]; then
            pass "Cron delivery: all jobs use canonical 'to' field"
        else
            fail "Cron delivery: jobs using 'target' instead of 'to': $(echo "$cron_field_check" | tr '|' ', ')"
        fi
    else
        skip "Cron delivery field: no container access"
    fi
}
