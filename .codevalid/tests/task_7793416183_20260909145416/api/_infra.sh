#!/usr/bin/env bash
# Seed-test infra script for task_7793416183_20260909145416 API cases
set -euo pipefail

# Export DATABASE_URL consistent with docker-compose
export DATABASE_URL="postgresql://app:app@toxiproxy:5432/appdb"

# Helper: read app PORT from .codevalid/docker-compose.yml
get_app_port_from_compose() {
  local compose_path="$1"
  # Use yq if available; otherwise parse via awk/grep assuming simple structure
  if command -v yq >/dev/null 2>&1; then
    yq '.services.app.environment.PORT' "$compose_path"
  else
    awk '/^\s*app:/{flag=1} flag && /PORT:/ {gsub("\"", "", $2); print $2; exit}' "$compose_path"
  fi
}

# Helper: wait for a TCP host:port
wait_for_tcp() {
  local hp="$1"
  local host="${hp%%:*}"
  local port="${hp##*:}"
  echo "waiting for TCP ${host}:${port} ..."
  until nc -z "$host" "$port"; do
    sleep 1
  done
}

# Helper: wait for an HTTP URL returning 2xx
wait_for_http() {
  local url="$1"
  echo "waiting for HTTP ${url} ..."
  until curl -fsS "$url" >/dev/null 2>&1; do
    sleep 1
  done
}
