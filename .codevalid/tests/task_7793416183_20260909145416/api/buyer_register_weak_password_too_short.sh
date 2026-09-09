#!/usr/bin/env bash
set -euo pipefail

# Setup
source tests/task_7793416183_20260909145416/api/_infra.sh

read_repo_file() {
  local path="$1"
  cat "$path"
}

COMPOSE_PATH=".codevalid/docker-compose.yml"
APP_PORT="$(get_app_port_from_compose "${COMPOSE_PATH}")"
APP_BASE_URL="http://app:${APP_PORT}"

CASE_ID="buyer_register_weak_password_too_short"

# Preconditions
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE email = 'weakpass_buyer@example.com';"

# When
curl -sS -o /tmp/resp.json -w "%{http_code}" \
  -X POST "${APP_BASE_URL}/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "weakpass_buyer@example.com",
    "password": "short",
    "role": "BUYER"
  }' > /tmp/status_code.txt

# Then
STATUS_CODE="$(cat /tmp/status_code.txt)"
jq . /tmp/resp.json > /tmp/resp.pretty.json

if [ "$STATUS_CODE" -ne 400 ]; then
  echo "Expected HTTP 400, got ${STATUS_CODE}"
  exit 1
fi

ERROR_MSG="$(jq -r '.error // empty' /tmp/resp.json)"
if [ -z "$ERROR_MSG" ]; then
  echo "Expected non-empty error message in response JSON"
  exit 1
fi

USER_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM users WHERE email = 'weakpass_buyer@example.com';")"
if [ "$USER_COUNT" != "0" ]; then
  echo "Expected no user row for weakpass_buyer@example.com, found ${USER_COUNT}"
  exit 1
fi

# Teardown
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE email = 'weakpass_buyer@example.com';"
rm -f /tmp/resp.json /tmp/resp.pretty.json /tmp/status_code.txt

echo "CODEVALID_TEST_ASSERTION_OK:${CASE_ID}"
