#!/usr/bin/env bash
# Shared API test infra helpers for task_8469147088_20260901212727.
set -euo pipefail
export BASE_URL="${BASE_URL:-http://app:6713}"
export APP_BASE_URL="${APP_BASE_URL:-${BASE_URL}}"
export DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
