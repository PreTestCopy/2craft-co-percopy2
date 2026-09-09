#!/usr/bin/env bash
set -euo pipefail

# Infra setup for Buyer Account Login Authentication Flow tests
# Exports DATABASE_URL and APP_PORT consistent with .codevalid/docker-compose.yml

export DATABASE_URL="postgresql://app:app@toxiproxy:5432/appdb"
export APP_PORT="6713"

# Ensure required CLI tools are present (psql, jq, curl)
command -v psql >/dev/null 2>&1 || { echo "psql not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl not found" >&2; exit 1; }
