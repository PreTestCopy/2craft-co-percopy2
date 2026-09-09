#!/usr/bin/env bash
set -euo pipefail

# Infra script for task_7793416183_20260909145416 API tests
# Provides DATABASE_URL and helpers used by test scripts.

# Export DATABASE_URL consistent with docker-compose.yml
# services.app.environment.DATABASE_URL
export DATABASE_URL="postgresql://app:app@toxiproxy:5432/appdb"

# Helper: extract app port from compose file.
# The compose uses environment PORT: "6713" and healthcheck on 6713.
# We parse the PORT value; if parsing fails, default to 6713.
get_app_port_from_compose() {
  local compose_path="$1"
  if [ -f "$compose_path" ]; then
    local port
    port="$(grep -A5 "app:" "$compose_path" | grep "PORT:" | head -n1 | sed -E 's/.*PORT:\s*"?([0-9]+)"?.*/\1/')" || true
    if [[ -n "$port" ]]; then
      echo "$port"
      return 0
    fi
  fi
  # Fallback to known test port
  echo "6713"
}

