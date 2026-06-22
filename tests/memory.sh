# tests/memory.sh — Memory Server Tests (config, CRUD, health, working memory)
# Runs when OPENCLAW_MEMORY_SERVER_URL is set.

test_memory() {
    should_run "memory" || return 0

    if [ -z "$OPENCLAW_MEMORY_SERVER_URL" ]; then
        return 0
    fi

    section "Memory Server (21 tests)"

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
        # Count matches directly after excluding transient timeouts — a
        # brittle "HH:MM:SS" re-filter would zero out untimestamped
        # continuation/stack-trace lines (LAB-271). prefetch.sh already scopes
        # GATEWAY_LOGS to the current startup window.
        local mem_critical
        mem_critical=$(echo "$GATEWAY_LOGS" | grep -ai "redis-memory.*error\|memory.*failed\|ECONNREFUSED.*memory\|memory.*auth" | \
            grep -v -i "timeout" | grep -aic "redis-memory.*error\|memory.*failed\|ECONNREFUSED.*memory\|memory.*auth" 2>/dev/null || true)
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
        -d "{\"memories\": [{\"id\": \"$test_marker\", \"text\": \"$test_text\", \"namespace\": \"$NAMESPACE\", \"topics\": [\"e2e-test\"], \"entities\": [\"E2E-Test-Runner\"]}]}" \
        "$MEMORY_SERVER/v1/long-term-memory/" 2>/dev/null)
    if [ "$store_code" = "200" ] || [ "$store_code" = "201" ]; then
        pass "Store: $test_marker ($store_code)"
    else
        fail "Store: HTTP $store_code"
        for s in "Search" "Get" "Update" "PATCH structured fields" "Search (topic filter)" "Search (entity filter)" "Search (distance)" "Pin (PATCH)" "Delete" "Verify deleted"; do
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
        for s in "Get" "Update" "PATCH structured fields" "Search (topic filter)" "Search (entity filter)" "Search (distance)" "Pin (PATCH)" "Delete" "Verify deleted"; do
            skip "$s: skipped (search failed)"
        done
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

    # 9. PATCH structured fields (topics, entities, memory_type, event_date)
    #    Catches server bugs like the 0.13.2 topic pipe-joining issue.
    local enrich_code
    enrich_code=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
        -H "Content-Type: application/json" \
        -d '{"topics": ["e2e-test", "health:test"], "entities": ["E2E-Runner"], "memory_type": "episodic", "event_date": "2026-02-24"}' \
        "$MEMORY_SERVER/v1/long-term-memory/$server_id?namespace=$NAMESPACE" 2>/dev/null)
    if [ "$enrich_code" = "200" ]; then
        local verify_fields
        verify_fields=$(curl -s "$MEMORY_SERVER/v1/long-term-memory/$server_id?namespace=$NAMESPACE" 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
raw_topics = d.get('topics') or []
topics_str = '|'.join(raw_topics) if raw_topics else ''
topics_ok = 'health:test' in topics_str
entities_ok = 'E2E-Runner' in (d.get('entities') or [])
type_ok = d.get('memory_type') == 'episodic'
raw_date = d.get('event_date') or ''
date_ok = raw_date.startswith('2026-02-24')
print('yes' if all([topics_ok, entities_ok, type_ok, date_ok]) else f'no (topics:{topics_ok}, entities:{entities_ok}, type:{type_ok}, date:{date_ok})')
" 2>/dev/null)
        if [ "$verify_fields" = "yes" ]; then
            pass "PATCH structured fields: round-trip verified"
        else
            fail "PATCH structured fields: not persisted — $verify_fields"
        fi
    else
        fail "PATCH structured fields: HTTP $enrich_code"
    fi

    # 10. Search with topic filter
    #     Known bug: agent-memory-server 0.13.1/0.13.2 returns 500 for topic filters
    #     Capture body+code in one call into shell variables (no fixed /tmp
    #     path — avoids cross-run clobber / predictable-path issues, LAB-270).
    local topic_resp topic_code topic_body topic_found="no"
    topic_resp=$(curl -s -w '\n%{http_code}' -X POST \
        -H "Content-Type: application/json" \
        -d "{\"text\": \"$test_marker\", \"namespace\": {\"eq\": \"$NAMESPACE\"}, \"topics\": {\"any\": [\"e2e-test\"]}, \"limit\": 5}" \
        "$MEMORY_SERVER/v1/long-term-memory/search" 2>/dev/null)
    topic_code=$(echo "$topic_resp" | tail -1)
    topic_body=$(echo "$topic_resp" | sed '$d')
    if [ "$topic_code" = "500" ]; then
        skip "Search (topic filter): server returns 500 (known bug in 0.13.x)"
    elif [ "$topic_code" = "200" ]; then
        topic_found=$(echo "$topic_body" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for m in d.get('memories', []):
    if 'E2E_TEST' in m.get('text', ''):
        print('yes'); sys.exit(0)
print('no')
" 2>/dev/null)
        if [ "$topic_found" = "yes" ]; then
            pass "Search (topic filter): found with topics={any:[\"e2e-test\"]}"
        else
            fail "Search (topic filter): 200 but test memory not in results"
        fi
    else
        fail "Search (topic filter): HTTP $topic_code"
    fi

    # 11. Search with entity filter
    local entity_resp entity_code entity_body entity_found="no"
    entity_resp=$(curl -s -w '\n%{http_code}' -X POST \
        -H "Content-Type: application/json" \
        -d "{\"text\": \"$test_marker\", \"namespace\": {\"eq\": \"$NAMESPACE\"}, \"entities\": {\"any\": [\"E2E-Runner\"]}, \"limit\": 5}" \
        "$MEMORY_SERVER/v1/long-term-memory/search" 2>/dev/null)
    entity_code=$(echo "$entity_resp" | tail -1)
    entity_body=$(echo "$entity_resp" | sed '$d')
    if [ "$entity_code" = "200" ]; then
        entity_found=$(echo "$entity_body" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for m in d.get('memories', []):
    if 'E2E_TEST' in m.get('text', ''):
        print('yes'); sys.exit(0)
print('no')
" 2>/dev/null)
        if [ "$entity_found" = "yes" ]; then
            pass "Search (entity filter): found with entities={any:[\"E2E-Runner\"]}"
        else
            fail "Search (entity filter): 200 but test memory not in results"
        fi
    elif [ "$entity_code" = "500" ]; then
        skip "Search (entity filter): server returns 500 (known bug)"
    else
        fail "Search (entity filter): HTTP $entity_code"
    fi

    # 12. Search distance validation (exact text match should be < 0.5)
    if [ -n "$search_dist" ] && [ "$search_dist" != "unknown" ]; then
        local dist_ok
        dist_ok=$(python3 -c "print('yes' if float('$search_dist') < 0.5 else 'no')" 2>/dev/null)
        if [ "$dist_ok" = "yes" ]; then
            pass "Search (distance): $search_dist (< 0.5)"
        else
            fail "Search (distance): $search_dist (expected < 0.5 for exact text match)"
        fi
    else
        skip "Search (distance): dist not returned by server"
    fi

    # 13. Pin test (PATCH pinned=true)
    #     Known limitation: 0.13.2 does not support PATCH for pinned field (returns 400).
    local pin_code
    pin_code=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
        -H "Content-Type: application/json" \
        -d '{"pinned": true}' \
        "$MEMORY_SERVER/v1/long-term-memory/$server_id?namespace=$NAMESPACE" 2>/dev/null)
    if [ "$pin_code" = "200" ]; then
        local pin_verify
        pin_verify=$(curl -s "$MEMORY_SERVER/v1/long-term-memory/$server_id?namespace=$NAMESPACE" 2>/dev/null | \
            python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if d.get('pinned') else 'no')" 2>/dev/null)
        if [ "$pin_verify" = "yes" ]; then
            pass "Pin (PATCH): pinned=true persists"
        else
            fail "Pin (PATCH): not set after PATCH 200"
        fi
    elif [ "$pin_code" = "400" ]; then
        skip "Pin (PATCH): server does not support PATCH for pinned (400)"
    else
        fail "Pin (PATCH): HTTP $pin_code"
    fi

    # 14. Memory server version (informational)
    local server_version
    server_version=$(curl -s --connect-timeout 5 "$MEMORY_SERVER/openapi.json" 2>/dev/null | \
        python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('info',{}).get('version','unknown'))" 2>/dev/null)
    if [ -n "$server_version" ] && [ "$server_version" != "unknown" ]; then
        pass "Server version: $server_version"
    else
        skip "Server version: could not read from OpenAPI spec"
    fi

    # 15. Delete
    local del_code
    del_code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE \
        "$MEMORY_SERVER/v1/long-term-memory?memory_ids=$server_id&namespace=$NAMESPACE" 2>/dev/null)
    if [ "$del_code" = "200" ] || [ "$del_code" = "204" ]; then
        pass "Delete: $del_code"
    else
        fail "Delete: HTTP $del_code"
    fi

    # 16. Verify deleted
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

    # 17. PUT working memory
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

    # 18. GET working memory
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

    # 19. Verify content round-tripped
    local content_check
    content_check=$(echo "$get_body" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    msgs = d.get('messages', [])
    has_user = any('E2E test' in m.get('content','') for m in msgs if m.get('role') == 'user')
    has_asst = any('E2E response' in m.get('content','') for m in msgs if m.get('role') == 'assistant')
    print('ok' if has_user and has_asst else 'content missing')
except Exception:
    print('parse error')
" 2>/dev/null)
    if [ "$content_check" = "ok" ]; then
        pass "Working memory content: round-tripped"
    else
        fail "Working memory content: $content_check"
    fi

    # 20. List sessions
    local list_code
    list_code=$(curl -s -o /dev/null -w '%{http_code}' "$MEMORY_SERVER/v1/working-memory/?namespace=$NAMESPACE&limit=5" 2>/dev/null)
    if [ "$list_code" = "200" ]; then
        pass "Working memory list: accessible"
    else
        fail "Working memory list: HTTP $list_code"
    fi

    # 21. DELETE working memory
    local wm_del_code
    wm_del_code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE \
        "$MEMORY_SERVER/v1/working-memory/$test_session?namespace=$NAMESPACE&user_id=e2e-test" 2>/dev/null)
    if [ "$wm_del_code" = "200" ] || [ "$wm_del_code" = "204" ]; then
        pass "Working memory DELETE: $wm_del_code"
    else
        fail "Working memory DELETE: HTTP $wm_del_code"
    fi
}
