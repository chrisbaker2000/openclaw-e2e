# tests/custom-provider.sh — Custom Provider Endpoint Tests
# Runs when OPENCLAW_CUSTOM_PROVIDER_* vars are set.
# Use this to test AWS Bedrock or any custom model provider.

test_custom_provider() {
    should_run "custom-provider" || return 0

    if [ -z "$OPENCLAW_CUSTOM_PROVIDER_URL" ] || [ -z "$OPENCLAW_CUSTOM_PROVIDER_KEY" ]; then
        return 0
    fi

    local provider_name="${OPENCLAW_CUSTOM_PROVIDER_NAME:-custom}"
    local models="${OPENCLAW_CUSTOM_PROVIDER_MODELS:-}"

    # Count models to test.
    # Use printf (adds a trailing newline) so a comma-separated list like
    # "a,b" counts as 2, not 1 — keeps the advertised header count in sync
    # with the number of per-model assertions actually run below.
    local model_count=0
    if [ -n "$models" ]; then
        model_count=$(printf '%s\n' "$models" | tr ',' '\n' | grep -c '[^[:space:]]')
    fi

    local test_count=$((model_count + 1))
    section "Custom Provider: $provider_name ($test_count tests)"

    # 1. Endpoint reachable
    local base_code
    base_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 \
        -X POST "$OPENCLAW_CUSTOM_PROVIDER_URL" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $OPENCLAW_CUSTOM_PROVIDER_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -d '{"model":"test","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' 2>/dev/null)
    # Any response (even 400/404) means endpoint is reachable
    if [ -n "$base_code" ] && [ "$base_code" != "000" ]; then
        pass "Endpoint reachable: HTTP $base_code"
    else
        fail "Endpoint unreachable: ${base_code:-timeout}"
        return 0
    fi

    # Test each model.
    # NOTE: loop runs in the CURRENT shell (process substitution, not a pipe)
    # so pass()/fail() mutate PASS_COUNT/FAIL_COUNT/FAILURES in lib/output.sh.
    # A `... | while read` pipeline would run the body in a subshell and the
    # counts would be lost — a broken/unreachable model would silently pass.
    if [ -n "$models" ]; then
        while read -r model; do
            model=$(echo "$model" | tr -d ' ')
            [ -z "$model" ] && continue
            local model_code
            model_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 \
                -X POST "$OPENCLAW_CUSTOM_PROVIDER_URL" \
                -H "Content-Type: application/json" \
                -H "x-api-key: $OPENCLAW_CUSTOM_PROVIDER_KEY" \
                -H "anthropic-version: 2023-06-01" \
                -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply OK\"}],\"max_tokens\":5}" 2>/dev/null)
            if [ "$model_code" = "200" ]; then
                pass "$model: responds (200)"
            elif [ "$model_code" = "429" ]; then
                pass "$model: rate limited but alive (429)"
            else
                fail "$model: HTTP ${model_code:-timeout}"
            fi
        done < <(printf '%s\n' "$models" | tr ',' '\n')
    fi
}
