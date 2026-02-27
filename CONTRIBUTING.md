# Contributing to OpenClaw E2E

Thanks for your interest in improving the OpenClaw E2E test suite! This project helps the community catch regressions after updates, and contributions make it better for everyone.

## Getting Started

1. Fork and clone the repo
2. Copy `.env.example` to `.env` and configure for your deployment (or run `./setup.sh`)
3. Run `./openclaw-test.sh` to verify everything works

## Adding New Tests

### Where to put them

Each test module in `tests/` covers a specific domain:

| File | Domain | Requires |
|------|--------|----------|
| `core.sh` | Gateway health, HTTP, version | Gateway URL |
| `config.sh` | Config schema validation | Container access |
| `cron.sh` | Cron job delivery config | Container access |
| `plugins.sh` | Plugin manifests and registration | Container access |
| `memory.sh` | Memory server CRUD | Memory server URL |
| `channels.sh` | Slack/Discord connectivity | Explicitly enabled |
| `runtime.sh` | Container runtime checks | Container access |
| `environment.sh` | Env vars, log scanning | Container access |
| `context.sh` | Workspace .md budgets, bloat detection | Container access |
| `latency.sh` | Performance benchmarks | Gateway URL |
| `custom-provider.sh` | Custom provider endpoints | Provider config |

### Test patterns

Use the helper functions from `lib/output.sh`:

```bash
# Simple pass/fail
if [ "$result" = "expected" ]; then
    pass "Description of what passed"
else
    fail "Description of what failed: got $result"
fi

# Skip when prerequisites aren't met
if [ -z "$SOME_CONFIG" ]; then
    skip "Test name: config not set"
    return 0
fi
```

### Guidelines

1. **Guard prerequisites** — Use `has_container_access` or check config vars. Tests should skip, not fail, when features aren't configured.
2. **Use the transport layer** — Call `container_exec`, `container_logs`, `host_exec` from `lib/transport.sh` instead of raw SSH/Docker commands.
3. **Ground in docs-schema.json** — Validate against schema values, not hardcoded strings. This keeps tests accurate when OpenClaw updates.
4. **Update the section header** — When adding tests to a module, update the test count in the `section "..."` call.
5. **Keep tests fast** — The full suite should run in under 2 minutes. Avoid unnecessary sleeps.

### Example: adding a new config validation

```bash
# In tests/config.sh, inside test_config():

# N. New setting valid (per docs: value1, value2, value3)
local new_check
new_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
schema = json.load(open('$DOCS_SCHEMA'))
valid = set(schema['new_section']['valid_values'])
config = json.load(sys.stdin)
value = config.get('some', {}).get('setting', '')
if not value or value in valid:
    print('ok')
else:
    print(f'invalid: {value}')
" 2>/dev/null)
if [ "$new_check" = "ok" ]; then
    pass "New setting: valid"
else
    fail "New setting $new_check"
fi
```

## Updating docs-schema.json

When OpenClaw releases a new version with config changes:

1. Check [docs.openclaw.ai](https://docs.openclaw.ai) for updated enums, defaults, and valid values
2. Update the relevant section in `docs-schema.json`
3. Update `_compatible_versions` at the top
4. Add or update tests that reference the changed values

## Pull Requests

- One feature or fix per PR
- Include what you tested (which sections, what deployment type)
- Update test counts in section headers if you added tests
- Keep commits focused with clear messages

## Reporting Issues

Use the [bug report template](https://github.com/chrisbaker2000/openclaw-e2e/issues/new?template=bug_report.md) for test failures or incorrect validations. Include:

- Your OpenClaw version
- Your deployment type (local Docker, SSH, API-only)
- The full test output (or the relevant section)
- Your `.env` configuration (redact secrets)

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Be respectful and constructive.
