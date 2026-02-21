# Security Policy

## Scope

This project is a **test suite** (bash scripts) — it does not run as a service or handle user data. Security concerns here would involve:

- Test scripts that could inadvertently expose secrets from `.env` files
- `docs-schema.json` containing incorrect validation values that could mask real config vulnerabilities
- Transport layer (`lib/transport.sh`) executing unintended commands via SSH/Docker

## Reporting a Vulnerability

If you find a security issue, please report it by [opening a private security advisory](https://github.com/chrisbaker2000/openclaw-e2e/security/advisories/new) on this repository.

Do **not** open a public issue for security vulnerabilities.

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.x     | Yes       |

## Best Practices for Users

- **Never commit your `.env` file** — it's in `.gitignore` for a reason
- Review `setup.sh` output before running tests against production gateways
- The `container_exec` transport runs commands inside your Docker container — review any test modifications before running
