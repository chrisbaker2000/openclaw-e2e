# OpenClaw E2E Test Suite

> **Note**: The homelab gateway runs **natively on the Mac Mini M4 Pro** (not in Docker). For homelab testing, use the local test suite at `~/.openclaw/bin/openclaw-test.sh` (200+ tests). This E2E suite is designed for testing Docker-based or remote gateway deployments.

Post-update end-to-end tests for [OpenClaw](https://openclaw.ai) gateway deployments. Catches regressions after updates, config changes, or infrastructure modifications.

**~117 tests across 11 categories** — runs in under 2 minutes. Zero dependencies beyond `bash`, `curl`, and `python3`.

## Quick Start

```bash
git clone https://github.com/chrisbaker2000/openclaw-e2e.git
cd openclaw-e2e

# Interactive setup (auto-detects your deployment)
./setup.sh

# Run tests
./openclaw-test.sh
```

Or set up manually:

```bash
cp .env.example .env
# Edit .env with your gateway URL and access method
./openclaw-test.sh
```

## Sample Output

```
╔══════════════════════════════════════╗
║   OpenClaw Post-Update E2E Tests     ║
╚══════════════════════════════════════╝
Gateway:   http://localhost:18789
Container: local → openclaw-gateway

━━━ Gateway Core (7 tests) ━━━
  ✓ HTTP responds: 200
  ✓ Health status: healthy
  ✓ Version: 2026.2.27
  ✓ CPU: 2.13% (< 50%)
  ✓ Memory: 460.5MiB
  ✓ PIDs: 12 (3-100 range)
  ✓ Healthcheck: configured

━━━ Config Schema Compliance (22 tests) ━━━
  ✓ Shared config: all required sections present
  ✓ Primary model format: valid provider/model pattern
  ...

━━━ Memory Server (21 tests) ━━━
  ✓ Memory server health: OK
  ✓ Store: OPENCLAW_E2E_TEST_1772217571 (200)
  ○ Search (topic filter): server returns 500 (known bug in 0.13.x) (skipped)
  ...

════════════════════════════════════════
  106 passed, 0 failed, 3 skipped
════════════════════════════════════════
```

Tests **skip** (not fail) when a feature isn't configured. Start with just a gateway URL and add more as needed.

## What It Tests

| Section | Tests | What It Checks |
|---------|:-----:|----------------|
| **Core** | 7 | Gateway health, HTTP response, version, resource usage |
| **Config** | 22 | Schema compliance against [official docs](https://docs.openclaw.ai) — model format, providers, auth/bind/reload modes, session settings |
| **Cron** | 13 | Delivery config, channels, schedules, session targets |
| **Plugins** | 5 | Registration, manifests, configSchema validity |
| **Memory** | 21 | Health, CRUD round-trip, structured fields, working memory |
| **Channels** | 11 | Slack/Discord connectivity, policies, modes |
| **Runtime** | 7 | Node.js version, container stability, uptime, memory limit |
| **Environment** | 11 | Error scanning, dangerous flags, security violations |
| **Context** | 8 | Workspace .md budgets, bloat detection, token estimation |
| **Latency** | 5 | Gateway HTTP, memory search, skills compilation, startup time |
| **Custom Provider** | N | Endpoint reachability for Azure, Bedrock, etc. |

## Configuration

All settings live in `.env`. The only required value is your gateway URL:

```bash
OPENCLAW_GATEWAY_URL="http://localhost:18789"
```

Everything else is optional — tests skip cleanly when features aren't configured.

### Gateway Access

Gateway access enables config validation, cron, plugin, runtime, environment, and context tests. Choose one method:

**Method A: SSH + Docker** (gateway on a remote host — NAS, VPS, etc.)
```bash
OPENCLAW_SSH_HOST="user@host"
OPENCLAW_DOCKER_BIN="docker"
OPENCLAW_CONTAINER="openclaw-gateway"
```

**Method B: Local Docker** (gateway in Docker on this machine)
```bash
OPENCLAW_DOCKER_BIN="docker"
OPENCLAW_CONTAINER="openclaw-gateway"
```

**Method C: Native** (gateway runs directly on this machine, no Docker)
```bash
OPENCLAW_NATIVE=true
# OPENCLAW_MAC_CONFIG_DIR="$HOME/.openclaw"  # Default — change if non-standard
```
Reads config files and logs from disk. Runs ~80 of ~95 tests. Docker-specific tests (inspect, stats, healthcheck) skip gracefully.

**Method D: API-only** — leave all access vars empty. Only core HTTP, memory, and latency tests run (~36 tests).

### Optional Features

| Feature | Config | What It Enables |
|---------|--------|-----------------|
| Memory server | `OPENCLAW_MEMORY_SERVER_URL` | 21 CRUD, health, and working memory tests |
| Slack | `OPENCLAW_SLACK_ENABLED=true` | Slack connectivity and policy checks |
| Discord | `OPENCLAW_DISCORD_ENABLED=true` | Discord connectivity and policy checks |
| Version pin | `OPENCLAW_EXPECTED_VERSION` | Fails if gateway version doesn't match |
| Custom provider | `OPENCLAW_CUSTOM_PROVIDER_*` | Tests Azure Anthropic, Bedrock, etc. |

### Tuning Thresholds

All thresholds have sensible defaults. Adjust for your hardware:

```bash
# Latency thresholds (milliseconds)
OPENCLAW_MAX_GATEWAY_HTTP_MS=2000     # default
OPENCLAW_MAX_MEMORY_SEARCH_MS=3000    # default
OPENCLAW_MAX_HEALTH_MS=1000           # default
OPENCLAW_MAX_SKILLS_MS=3000           # default

# Context optimization (workspace .md file budgets)
OPENCLAW_MAX_WORKSPACE_MD_FILES=10    # default
OPENCLAW_MAX_WORKSPACE_MD_BYTES=8000  # default
OPENCLAW_MAX_BOOTSTRAP_TOKENS=2000    # default
```

See [`.env.example`](.env.example) for the full list, or [`examples/`](examples/) for deployment-specific templates.

## Running Specific Sections

```bash
./openclaw-test.sh --section core               # Single section
./openclaw-test.sh --section core,config,memory  # Multiple sections
./openclaw-test.sh --expected-version 2026.2.20  # Pin expected version
./openclaw-test.sh --gateway-url http://10.0.0.5:18789  # Override URL
```

Available sections: `core`, `config`, `cron`, `plugins`, `memory`, `channels`, `runtime`, `environment`, `context`, `latency`, `custom-provider`

## Deployment Examples

### Native Install (Mac Mini, Linux box, etc.)
```bash
OPENCLAW_GATEWAY_URL="http://localhost:18789"
OPENCLAW_NATIVE=true
OPENCLAW_MEMORY_SERVER_URL="https://memory.your-project.run.app"
OPENCLAW_SLACK_ENABLED=true
```

### Local Docker Compose
```bash
OPENCLAW_GATEWAY_URL="http://localhost:18789"
OPENCLAW_DOCKER_BIN="docker"
OPENCLAW_CONTAINER="openclaw-gateway"
OPENCLAW_SLACK_ENABLED=true
```

See [`examples/`](examples/) for ready-to-use `.env` templates:

- **[`local-docker.env`](examples/local-docker.env)** — Gateway running locally via Docker Compose
- **[`remote-ssh.env`](examples/remote-ssh.env)** — Gateway on a remote NAS/VPS via SSH
- **[`api-only.env`](examples/api-only.env)** — Cloud-hosted gateway, no container access

## How It Works

1. **Pre-fetch**: Caches gateway logs, config, inspect data, and stats in one batch to minimize SSH round-trips
2. **Transport layer**: Abstracts SSH+Docker, local Docker, native, and API-only access behind a unified interface (`lib/transport.sh`)
3. **Path abstraction**: Uses `_PROC_CONFIG_DIR` to resolve config paths correctly in both Docker (`/home/node/.openclaw`) and native (`~/.openclaw`) environments
4. **Schema validation**: Tests are grounded in `docs-schema.json` (extracted from official OpenClaw docs) rather than hardcoded values
5. **Graceful degradation**: Each test module checks whether its prerequisites are met and skips cleanly if not — Docker-only features (inspect, stats) skip automatically in native mode

## Adding Your Own Tests

Drop a `.sh` file in `tests/local/` (gitignored). Name your function `test_local_<filename>` and it runs automatically:

```bash
# tests/local/my-checks.sh
test_local_my_checks() {
    section "My Custom Tests (2 tests)"
    # your tests here using pass/fail/skip helpers
}
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for full guidelines.

## Requirements

- **bash** 4+ (macOS ships bash 3 — `brew install bash` or use `/bin/zsh`)
- **curl** (for HTTP tests)
- **python3** (for JSON parsing — no `jq` dependency)
- **ssh** (only if using SSH container access)
- **docker** CLI (only if using local container access)

## Contributing

Issues and PRs welcome. When adding new tests:

1. Place them in the appropriate `tests/*.sh` module
2. Use `pass`, `fail`, or `skip` from `lib/output.sh`
3. Guard with `has_container_access` or config var checks
4. Use `container_exec` / `container_logs` from `lib/transport.sh` for gateway operations
5. Use `$_PROC_CONFIG_DIR` instead of hardcoding `/home/node/.openclaw` — this resolves correctly in all modes
6. Prefer `docs-schema.json` values over hardcoded strings

## License

MIT
