# OpenClaw E2E Test Suite

Post-update end-to-end tests for [OpenClaw](https://openclaw.ai) gateway deployments. Catches regressions after updates, config changes, or infrastructure modifications.

**~75 tests across 10 categories** — runs in under 2 minutes. Zero dependencies beyond `bash`, `curl`, and `python3`.

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
| **Core** | Gateway health, HTTP, version, CPU, memory, PIDs | Gateway URL |
| **Config** | Schema compliance, model format, providers, auth modes | Container access |
| **Cron** | Delivery fields, channels, modes, schedules | Container access |
| **Plugins** | Registration, manifests, configSchema validity | Container access |
| **Memory** | Health, CRUD round-trip, working memory | Memory server URL |
| **Channels** | Slack/Discord connectivity and config | Explicitly enabled |
| **Runtime** | Node.js version, container stability, volumes | Container access |
| **Environment** | Env vars, error scanning, workspace health | Container access |
| **Latency** | Gateway HTTP, memory health/search benchmarks | Gateway + memory |
| **Custom Provider** | Endpoint reachability, per-model validation | Provider config |

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

Available sections: `core`, `config`, `cron`, `plugins`, `memory`, `channels`, `runtime`, `environment`, `latency`, `custom-provider`

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

## Updating `docs-schema.json`

The bundled `docs-schema.json` contains validation values extracted from the official OpenClaw documentation. When OpenClaw releases a new version with config changes:

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
