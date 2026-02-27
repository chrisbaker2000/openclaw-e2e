# OpenClaw E2E Test Suite

Post-update end-to-end tests for [OpenClaw](https://openclaw.ai) gateway deployments. Catches regressions after updates, config changes, or infrastructure modifications.

**~117 tests across 11 categories** — runs in under 2 minutes. Zero dependencies beyond `bash`, `curl`, and `python3`. All validations grounded in the [official OpenClaw docs](https://docs.openclaw.ai).

## Quick Start

```bash
git clone https://github.com/chrisbaker2000/openclaw-e2e.git
cd openclaw-e2e

# Option A: Interactive setup (recommended)
./setup.sh

# Option B: Manual setup
cp .env.example .env
# Edit .env with your values

# Run tests
./openclaw-test.sh
```

## What It Tests

| Section | Tests | Requires |
|---------|-------|----------|
| **Core** (7) | Gateway health, HTTP, version, CPU, memory, PIDs | Gateway URL |
| **Config** (22) | Schema compliance, model format, providers, auth/bind/reload modes, session reset/maintenance, message queue/typing/delay modes, tailscale, funnel cross-check, logging, thinking levels, tool visibility, cron delivery field | Container access |
| **Cron** (13) | Delivery fields, channels, modes, schedules, session targets, thinking levels, wake modes | Container access |
| **Plugins** (5) | Registration, manifests, configSchema validity | Container access |
| **Memory** (21) | Health, CRUD round-trip, structured field PATCH, topic/entity filter search, distance validation, pin support, server version, working memory | Memory server URL |
| **Channels** (11) | Slack/Discord connectivity, dmPolicy, groupPolicy, mode, streamMode, replyToMode | Explicitly enabled |
| **Runtime** (7) | Node.js version, container stability, volumes, user/uid, PID limits, uptime, memory limit | Container access |
| **Environment** (11) | Env vars, error scanning, workspace health, dangerous flags, file permissions, unrecognized keys, WebSocket security, node security violations | Container access |
| **Context** (8) | Workspace .md count/size, README/BOOTSTRAP bloat, stale doc detection, bootstrap token estimation, humanDelay, context headroom | Container access |
| **Latency** (5) | Gateway HTTP, memory health/search, skills compilation, gateway startup time | Gateway + memory |
| **Custom Provider** (N) | Endpoint reachability, per-model validation | Provider config |

Tests **skip** (not fail) when their feature isn't configured. Start with just a gateway URL and add more config as needed.

## Configuration

All configuration lives in a `.env` file. Copy `.env.example` to get started, or run `./setup.sh` to auto-detect your setup.

### Required

```bash
OPENCLAW_GATEWAY_URL="http://localhost:18789"
```

### Container Access (choose one method)

Container access enables config validation, cron, plugin, runtime, and environment tests.

**Method A: SSH to remote Docker host** (NAS, VPS, cloud server)
```bash
OPENCLAW_SSH_HOST="user@192.168.1.100"
OPENCLAW_DOCKER_BIN="docker"
OPENCLAW_CONTAINER="openclaw-gateway"
```

**Method B: Local Docker** (gateway on this machine)
```bash
OPENCLAW_DOCKER_BIN="docker"
OPENCLAW_CONTAINER="openclaw-gateway"
```

**Method C: API-only** — leave SSH and Docker vars empty. Only core and latency tests run.

### Optional Features

```bash
# Memory server (enables CRUD + health tests)
OPENCLAW_MEMORY_SERVER_URL="https://your-memory-server.run.app"
OPENCLAW_MEMORY_NAMESPACE="default"

# Channel connectivity (checks gateway logs for connection status)
OPENCLAW_SLACK_ENABLED=true
OPENCLAW_DISCORD_ENABLED=true

# Pin expected values for stricter validation
OPENCLAW_EXPECTED_VERSION="2026.2.20"
OPENCLAW_PRIMARY_PROVIDER="anthropic"

# Custom model provider endpoint test (Azure, Bedrock, etc.)
OPENCLAW_CUSTOM_PROVIDER_NAME="azure-anthropic"
OPENCLAW_CUSTOM_PROVIDER_URL="https://your-resource.ai.azure.com/anthropic/v1/messages"
OPENCLAW_CUSTOM_PROVIDER_KEY="your-api-key"
OPENCLAW_CUSTOM_PROVIDER_MODELS="claude-opus-4-6,claude-sonnet-4-6"

# Latency thresholds in milliseconds (adjust for your hardware)
OPENCLAW_MAX_GATEWAY_HTTP_MS=2000
OPENCLAW_MAX_MEMORY_SEARCH_MS=3000
OPENCLAW_MAX_HEALTH_MS=1000

# Context optimization thresholds (workspace .md file budgets)
OPENCLAW_MAX_WORKSPACE_MD_FILES=10
OPENCLAW_MAX_WORKSPACE_MD_BYTES=8000
OPENCLAW_MAX_BOOTSTRAP_TOKENS=2000
```

See [`.env.example`](.env.example) for the full list with documentation, or check [`examples/`](examples/) for deployment-specific templates.

## Running Specific Sections

```bash
# Single section
./openclaw-test.sh --section core

# Multiple sections
./openclaw-test.sh --section core,config,memory

# Pin expected version
./openclaw-test.sh --expected-version 2026.2.20

# Override gateway URL from CLI
./openclaw-test.sh --gateway-url http://10.0.0.5:18789
```

Available sections: `core`, `config`, `cron`, `plugins`, `memory`, `channels`, `runtime`, `environment`, `context`, `latency`, `custom-provider`

## Deployment Examples

### Local Docker Compose
```bash
OPENCLAW_GATEWAY_URL="http://localhost:18789"
OPENCLAW_DOCKER_BIN="docker"
OPENCLAW_CONTAINER="openclaw-gateway"
OPENCLAW_SLACK_ENABLED=true
```

### Remote NAS via SSH
```bash
OPENCLAW_GATEWAY_URL="http://192.168.1.100:18789"
OPENCLAW_SSH_HOST="admin@192.168.1.100"
OPENCLAW_DOCKER_BIN="/usr/bin/docker"
OPENCLAW_CONTAINER="openclaw-gateway"
OPENCLAW_MEMORY_SERVER_URL="https://memory.your-project.run.app"
```

### Cloud-Hosted (API-only)
```bash
OPENCLAW_GATEWAY_URL="https://your-gateway.example.com:18789"
OPENCLAW_MEMORY_SERVER_URL="https://memory.your-project.run.app"
```

## How It Works

1. **Pre-fetch**: Caches gateway logs, config, inspect data, and stats in one batch to minimize SSH round-trips
2. **Transport layer**: Abstracts SSH+Docker, local Docker, and API-only access behind a unified interface
3. **Schema validation**: Tests are grounded in `docs-schema.json` (extracted from official OpenClaw docs) rather than hardcoded values
4. **Graceful degradation**: Each test module checks whether its prerequisites are met and skips cleanly if not

## `docs-schema.json` — What's Validated

The bundled `docs-schema.json` contains all testable enums and values extracted from 16 official [OpenClaw docs](https://docs.openclaw.ai) pages. Tests reference this schema instead of hardcoding values, so updating one file keeps all tests current.

**Domains covered:**

| Domain | Validated Values |
|--------|-----------------|
| **Gateway** | auth modes, bind modes, reload modes, tailscale modes, funnel constraints, mDNS discovery |
| **Models** | 21 built-in providers, ref format regex, 4 API types, provider required fields, model aliases |
| **Agents** | thinking levels, time formats, bootstrap char limits, context/timeout defaults |
| **Cron** | delivery fields/channels/modes, schedule kinds, session targets, payload alignment, wake modes, thinking levels |
| **Session** | DM scopes, reset modes, maintenance modes |
| **Messages** | queue modes, typing modes, human delay modes, ack reaction scopes |
| **Tools** | profiles, visibility modes, exec host/security modes |
| **Sandbox** | modes, scopes, workspace access levels |
| **Channels** | DM/group policies, stream modes, reply-to modes, reaction notification modes, Slack/Discord-specific settings |
| **Security** | 9 operator scopes, file permissions, exec approval modes |
| **Plugins** | manifest required fields |
| **Docker** | default resource limits, runtime user/uid, DNS defaults |
| **Logging** | console styles, redaction modes |
| **Heartbeat** | default interval, OK token, ack max chars |
| **Memory** | provider priority, citation modes |

### Updating `docs-schema.json`

When OpenClaw releases a new version with config changes:

1. Check the [OpenClaw docs](https://docs.openclaw.ai) for updated values
2. Update the relevant sections in `docs-schema.json`
3. Update `_compatible_versions` to reflect the new version range

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
4. Use `container_exec` / `container_logs` from `lib/transport.sh` for container operations
5. Prefer `docs-schema.json` values over hardcoded strings

## License

MIT
