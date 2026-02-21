# tests/plugins.sh — Plugin Registration & Manifests
# Validates plugins are loaded and manifests are valid.

test_plugins() {
    should_run "plugins" || return 0
    has_container_access || return 0
    section "Plugins (5 tests)"

    # 1. No plugin registration failures
    if [ -n "$GATEWAY_LOGS" ]; then
        if echo "$GATEWAY_LOGS" | grep -qi "plugin failed during register\|plugin.*register.*fail\|failed to register plugin"; then
            fail "Plugin registration failure detected"
            echo "$GATEWAY_LOGS" | grep -i "plugin.*fail.*register\|failed.*register" | head -3 | sed 's/^/    /'
        else
            pass "No plugin registration failures"
        fi
    else
        skip "Plugin registration: logs not available"
    fi

    # 2. No schema validation errors
    if [ -n "$GATEWAY_LOGS" ]; then
        local schema_errors
        schema_errors=$(echo "$GATEWAY_LOGS" | grep -a "must NOT have additional properties\|additionalProperties" | grep -c "[0-9][0-9]:[0-9][0-9]:[0-9][0-9]" 2>/dev/null || true)
        schema_errors=$(echo "$schema_errors" | tr -d ' \n')
        if [ "${schema_errors:-0}" = "0" ]; then
            pass "No schema validation errors"
        else
            fail "Schema validation errors: $schema_errors occurrences"
            echo "$GATEWAY_LOGS" | grep -a "additional.*properties" | grep "[0-9][0-9]:[0-9][0-9]:[0-9][0-9]" | head -3 | sed 's/^/    /'
        fi
    else
        skip "Schema validation: logs not available"
    fi

    # 3. Plugin manifests have required fields (id, configSchema)
    if [ -f "$DOCS_SCHEMA" ]; then
        local manifest_check
        manifest_check=$(container_exec "python3 -c '
import json, os, glob
ext_dir = \"/home/node/.openclaw/extensions\"
bad = []
for plugin_dir in glob.glob(os.path.join(ext_dir, \"*/\")):
    manifest_path = os.path.join(plugin_dir, \"openclaw.plugin.json\")
    plugin_name = os.path.basename(plugin_dir.rstrip(\"/\"))
    if not os.path.exists(manifest_path):
        bad.append(f\"{plugin_name}: missing manifest\")
        continue
    try:
        with open(manifest_path) as f:
            manifest = json.load(f)
        for field in [\"id\", \"configSchema\"]:
            if field not in manifest:
                bad.append(f\"{plugin_name}: missing {field}\")
    except json.JSONDecodeError:
        bad.append(f\"{plugin_name}: invalid JSON\")
print(\"|\".join(bad) if bad else \"ok\")
'")
        if [ "$manifest_check" = "ok" ]; then
            pass "Plugin manifests: all have required fields"
        else
            fail "Manifest issues: $(echo "$manifest_check" | tr '|' ', ')"
        fi
    else
        skip "Plugin manifests: docs-schema.json not found"
    fi

    # 4. Plugin configSchema is valid JSON Schema object
    local schema_valid
    schema_valid=$(container_exec "python3 -c '
import json, os, glob
ext_dir = \"/home/node/.openclaw/extensions\"
bad = []
for plugin_dir in glob.glob(os.path.join(ext_dir, \"*/\")):
    manifest_path = os.path.join(plugin_dir, \"openclaw.plugin.json\")
    plugin_name = os.path.basename(plugin_dir.rstrip(\"/\"))
    if not os.path.exists(manifest_path):
        continue
    try:
        with open(manifest_path) as f:
            manifest = json.load(f)
        cs = manifest.get(\"configSchema\")
        if cs is None:
            continue
        if not isinstance(cs, dict):
            bad.append(f\"{plugin_name}: configSchema not an object\")
        elif cs.get(\"type\") != \"object\":
            bad.append(f\"{plugin_name}: configSchema.type not object\")
    except Exception:
        continue
print(\"|\".join(bad) if bad else \"ok\")
'")
    if [ "$schema_valid" = "ok" ]; then
        pass "Plugin configSchemas: all valid JSON Schema objects"
    else
        fail "configSchema issues: $(echo "$schema_valid" | tr '|' ', ')"
    fi

    # 5. Exec approvals file valid (if it exists)
    local approvals_check
    approvals_check=$(container_exec "python3 -c '
import json, os
path = \"/home/node/.openclaw/exec-approvals.json\"
if not os.path.exists(path):
    print(\"ok\")
else:
    try:
        with open(path) as f:
            data = json.load(f)
        issues = []
        if \"version\" not in data:
            issues.append(\"missing version\")
        print(\"|\".join(issues) if issues else \"ok\")
    except json.JSONDecodeError as e:
        print(f\"invalid JSON: {e}\")
'")
    if [ "$approvals_check" = "ok" ]; then
        pass "Exec approvals: valid structure"
    else
        fail "Exec approvals: $(echo "$approvals_check" | tr '|' ', ')"
    fi
}
