# tests/memory.sh — Memory Server Tests (config, CRUD, health, working memory)
# Runs when OPENCLAW_MEMORY_SERVER_URL is set.

test_memory() {
    should_run "memory" || return 0

    if [ -z "$OPENCLAW_MEMORY_SERVER_URL" ]; then
        return 0
    fi

    section "Memory Server (15 tests)"

    local MEMORY_SERVER="$OPENCLAW_MEMORY_SERVER_URL"
    local NAMESPACE="$OPENCLAW_MEMORY_NAMESPACE"

    # ─── Health ────────────────────────────────────────────────────
    # 1. Server health
    local health_resp
    health_resp=$(curl -s --connect-timeout 5 "$MEMORY_SERVER/v1/health" 2>/dev/null)
    if echo "$health_resp" | grep -q '"now"'; then
        pass "Memory server health: OK"
    else
        fail "Memory server health: unexpected response"
        return 0  # Skip remaining tests if server is down
    fi

    # 2. OpenAPI docs accessible
    local docs_code
    docs_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 "$MEMORY_SERVER/openapi.json" 2>/dev/null)
    if [ "$docs_code" = "200" ]; then
        pass "OpenAPI spec: accessible"
    else
        fail "OpenAPI spec: HTTP ${docs_code:-timeout}"
    fi

    # 3. Plugin config validation (if container access available)
    if has_container_access && [ -n "$GATEWAY_CONFIG" ]; then
        local configured_url
        configured_url=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('plugins',{}).get('entries',{}).get('openclaw-redis-agent-memory',{}).get('config',{}).get('serverUrl',''))
" 2>/dev/null)
        if [ "$configured_url" = "$MEMORY_SERVER" ]; then
            pass "Server URL: config matches"
        elif [ -n "$configured_url" ]; then
            fail "Server URL mismatch: config=$configured_url, expected=$MEMORY_SERVER"
        else
            skip "Server URL: not set in config"
        fi
    else
        skip "Server URL: no container access to check config"
    fi

    # 4. No critical memory errors in logs
    if has_container_access && [ -n "$GATEWAY_LOGS" ]; then
        local mem_critical
        mem_critical=$(echo "$GATEWAY_LOGS" | grep -ai "redis-memory.*error\|memory.*failed\|ECONNREFUSED.*memory\|memory.*auth" | \
            grep -v -i "timeout" | grep -c "[0-9][0-9]:[0-9][0-9]:[0-9][0-9]" 2>/dev/null || true)
        mem_critical=$(echo "$mem_critical" | tr -d ' \n')
        if [ "${mem_critical:-0}" = "0" ]; then
            pass "No critical memory errors in logs"
        else
            fail "Critical memory errors: $mem_critical"
        fi
    else
        skip "Memory errors: no logs to check"
    fi

    # ─── CRUD Round-Trip ───────────────────────────────────────────
    local ts
    ts=$(date +%s)
    local test_marker="OPENCLAW_E2E_TEST_${ts}"
    local test_text="$test_marker: Automated test memory for post-update validation"

    # Pre-clean old test memories
    local old_ids
    old_ids=$(curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"text\": \"OPENCLAW_E2E_TEST automated\", \"namespace\": {\"eq\": \"$NAMESPACE\"}, \"limit\": 10}" \
        "$MEMORY_SERVER/v1/long-term-memory/search" 2>/dev/null | python3 -c "
import json,sys
d = json.load(sys.stdin)
for m in d.get('memories',[]):
    if 'E2E_TEST' in m.get('text',''):
        print(m['id'])
" 2>/dev/null)
    for oid in $old_ids; do
        curl -s -o /dev/null -X DELETE "$MEMORY_SERVER/v1/long-term-memory?memory_ids=$oid&namespace=$NAMESPACE" 2>/dev/null
    done

    # 5. Store
    local store_code
    store_code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
        -H "Content-Type: application/json" \
        -d "{\"memories\": [{\"id\": \"$test_marker\", \"text\": \"$test_text\", \"namespace\": \"$NAMESPACE\", \"topics\": [\"e2e-test\"]}]}" \
        "$MEMORY_SERVER/v1/long-term-memory/" 2>/dev/null)
    if [ "$store_code" = "200" ] || [ "$store_code" = "201" ]; then
        pass "Store: $test_marker ($store_code)"
    else
        fail "Store: HTTP $store_code"
        for s in "Search" "Get" "Update" "Delete" "Verify deleted"; do
            skip "$s: skipped (store failed)"
        done
        # Skip remaining CRUD + working memory
        _test_memory_working
        return 0
    fi

    # 6. Search (with retry for indexing delay)
    local server_id="" search_dist=""
    for attempt in 1 2 3; do
        sleep 4
        local search_resp
        search_resp=$(curl -s -X POST -H "Content-Type: application/json" \
            -d "{\"text\": \"$test_marker\", \"namespace\": {\"eq\": \"$NAMESPACE\"}, \"limit\": 5}" \
            "$MEMORY_SERVER/v1/long-term-memory/search" 2>/dev/null)
        read -r server_id search_dist < <(echo "$search_resp" | python3 -c "
import json, sys
d = json.load(sys.stdin)
mems = d.get('memories', d if isinstance(d, list) else [])
for m in mems:
    if '$test_marker' in m.get('text', ''):
        print(m['id'], m.get('dist', 'unknown'))
        sys.exit(0)
sys.exit(1)
" 2>/dev/null)
        [ -n "$server_id" ] && break
    done
    if [ -n "$server_id" ]; then
        pass "Search: found ($server_id)"
    else
        fail "Search: test memory not found after 3 attempts"
        skip "Get: skipped"; skip "Update: skipped"; skip "Delete: skipped"; skip "Verify deleted: skipped"
        _test_memory_working
        return 0
    fi

    # 7. Get by ID
    local get_code
    get_code=$(curl -s -o /dev/null -w '%{http_code}' \
        "$MEMORY_SERVER/v1/long-term-memory/$server_id?namespace=$NAMESPACE" 2>/dev/null)
    if [ "$get_code" = "200" ]; then
        pass "Get: record retrieved"
    else
        fail "Get: HTTP $get_code"
    fi

    # 8. Update (PATCH)
    local updated_text="${test_marker}_UPDATED"
    local patch_code
    patch_code=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
        -H "Content-Type: application/json" \
        -d "{\"text\": \"$updated_text\"}" \
        "$MEMORY_SERVER/v1/long-term-memory/$server_id?namespace=$NAMESPACE" 2>/dev/null)
    if [ "$patch_code" = "200" ]; then
        local verify_text
        verify_text=$(curl -s "$MEMORY_SERVER/v1/long-term-memory/$server_id?namespace=$NAMESPACE" 2>/dev/null | \
            python3 -c "import json,sys; print(json.load(sys.stdin).get('text',''))" 2>/dev/null)
        if echo "$verify_text" | grep -q "_UPDATED"; then
            pass "Update (PATCH): verified"
        else
            fail "Update: PATCH 200 but text not updated"
        fi
    else
        fail "Update: HTTP $patch_code"
    fi

    # 9. Delete
    local del_code
    del_code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE \
        "$MEMORY_SERVER/v1/long-term-memory?memory_ids=$server_id&namespace=$NAMESPACE" 2>/dev/null)
    if [ "$del_code" = "200" ] || [ "$del_code" = "204" ]; then
        pass "Delete: $del_code"
    else
        fail "Delete: HTTP $del_code"
    fi

    # 10. Verify deleted
    sleep 1
    local verify_code
    verify_code=$(curl -s -o /dev/null -w '%{http_code}' \
        "$MEMORY_SERVER/v1/long-term-memory/$server_id?namespace=$NAMESPACE" 2>/dev/null)
    if [ "$verify_code" = "404" ]; then
        pass "Verify deleted: 404"
    elif [ "$verify_code" = "200" ]; then
        fail "Verify deleted: still returns 200"
    else
        pass "Verify deleted: $verify_code"
    fi

    # ─── Working Memory ────────────────────────────────────────────
    _test_memory_working
}

_test_memory_working() {
    local MEMORY_SERVER="$OPENCLAW_MEMORY_SERVER_URL"
    local NAMESPACE="$OPENCLAW_MEMORY_NAMESPACE"
    local ts
    ts=$(date +%s)
    local test_session="e2e-test-session-${ts}"

    # 11. PUT working memory
    local put_code
    put_code=$(curl -s -o /dev/null -w '%{http_code}' -X PUT \
        -H "Content-Type: application/json" \
        -d "{
            \"messages\": [
                {\"role\": \"user\", \"content\": \"E2E test from $test_session\", \"id\": \"msg-1\"},
                {\"role\": \"assistant\", \"content\": \"E2E response\", \"id\": \"msg-2\"}
            ],
            \"namespace\": \"$NAMESPACE\",
            \"user_id\": \"e2e-test\",
            \"tokens\": 50
        }" \
        "$MEMORY_SERVER/v1/working-memory/$test_session" 2>/dev/null)
    if [ "$put_code" = "200" ] || [ "$put_code" = "201" ]; then
        pass "Working memory PUT: $put_code"
    else
        fail "Working memory PUT: HTTP $put_code"
        skip "Working memory GET: skipped"; skip "Working memory content: skipped"
        skip "Working memory list: skipped"; skip "Working memory DELETE: skipped"
        return 0
    fi

    # 12. GET working memory
    local get_resp get_code get_body
    get_resp=$(curl -s -w '\n%{http_code}' \
        "$MEMORY_SERVER/v1/working-memory/$test_session?namespace=$NAMESPACE&user_id=e2e-test" 2>/dev/null)
    get_code=$(echo "$get_resp" | tail -1)
    get_body=$(echo "$get_resp" | sed '$d')
    if [ "$get_code" = "200" ]; then
        pass "Working memory GET: retrieved"
    else
        fail "Working memory GET: HTTP $get_code"
    fi

    # 13. Verify content round-tripped
    local content_check
    content_check=$(echo "$get_body" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    msgs = d.get('messages', [])
    has_user = any('E2E test' in m.get('content','') for m in msgs if m.get('role') == 'user')
    has_asst = any('E2E response' in m.get('content','') for m in msgs if m.get('role') == 'assistant')
    print('ok' if has_user and has_asst else 'content missing')
except:
    print('parse error')
" 2>/dev/null)
    if [ "$content_check" = "ok" ]; then
        pass "Working memory content: round-tripped"
    else
        fail "Working memory content: $content_check"
    fi

    # 14. List sessions
    local list_code
    list_code=$(curl -s -o /dev/null -w '%{http_code}' "$MEMORY_SERVER/v1/working-memory/?namespace=$NAMESPACE&limit=5" 2>/dev/null)
    if [ "$list_code" = "200" ]; then
        pass "Working memory list: accessible"
    else
        fail "Working memory list: HTTP $list_code"
    fi

    # 15. DELETE working memory
    local wm_del_code
    wm_del_code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE \
        "$MEMORY_SERVER/v1/working-memory/$test_session?namespace=$NAMESPACE&user_id=e2e-test" 2>/dev/null)
    if [ "$wm_del_code" = "200" ] || [ "$wm_del_code" = "204" ]; then
        pass "Working memory DELETE: $wm_del_code"
    else
        fail "Working memory DELETE: HTTP $wm_del_code"
    fi
}
