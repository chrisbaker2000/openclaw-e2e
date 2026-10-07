# tests/custom-provider.sh — Custom Provider Endpoint Tests
# Runs when OPENCLAW_CUSTOM_PROVIDER_* vars are set.
# Use this to test AWS Bedrock or any custom model provider.

# POST a minimal Messages request to the custom provider; prints the HTTP status
# (000 / empty on network failure).
# Usage: _custom_provider_probe MODEL PROMPT MAX_TOKENS
#
# Why stdin headers: an `-H "x-api-key: $KEY"` argument is world-readable via `ps`
# for the life of the request. The key header is written by the `printf` builtin
# (no process, no argv) into curl's stdin and read with `-H @-`.
# Why json.dumps: MODEL comes from config and was spliced into the JSON body raw,
# so a quote or backslash produced an invalid request (reported as a model failure).
_custom_provider_probe() {
    local model="$1" prompt="$2" max_tokens="$3" body
    body=$(python3 -c 'import json, sys
print(json.dumps({"model": sys.argv[1], "messages": [{"role": "user", "content": sys.argv[2]}], "max_tokens": int(sys.argv[3])}))' \
        "$model" "$prompt" "$max_tokens") || { echo "000"; return 0; }
    printf 'x-api-key: %s\n' "$OPENCLAW_CUSTOM_PROVIDER_KEY" | \
        curl -s --max-time "$OPENCLAW_HTTP_TIMEOUT" -o /dev/null -w '%{http_code}' --connect-timeout 10 \
            -X POST "$OPENCLAW_CUSTOM_PROVIDER_URL" \
            -H "Content-Type: application/json" \
            -H @- \
            -H "anthropic-version: 2023-06-01" \
            -d "$body" 2>/dev/null
}

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
    base_code=$(_custom_provider_probe "test" "hi" 1)
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
            model_code=$(_custom_provider_probe "$model" "Reply OK" 5)
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
