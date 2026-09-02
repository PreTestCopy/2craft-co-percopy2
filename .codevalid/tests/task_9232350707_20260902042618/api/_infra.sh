#!/usr/bin/env bash
# Shared API test infra helpers for catalog browsing tests.
set -euo pipefail
export APP_URL="${APP_URL:-http://app:6713}"
export BASE_URL="${BASE_URL:-http://app:6713}"
export DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
