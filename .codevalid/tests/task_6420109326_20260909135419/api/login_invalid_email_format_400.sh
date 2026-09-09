#!/usr/bin/env bash
set -euo pipefail

# Source shared infra helpers
source tests/task_6420109326_20260909135419/api/_infra.sh

# ---- Setup ---------------------------------------------------------------
# The plan requests these repo reads; they are no-ops for runtime but
# retained here to mirror the plan steps.
if [ -f .codevalid/docker-compose.yml ]; then
  : # placeholder to reflect read_repo_file .codevalid/docker-compose.yml
fi
if [ -f prisma/schema.prisma ]; then
  : # placeholder to reflect read_repo_file prisma/schema.prisma
fi
if [ -f prisma/migrations/0_init/migration.sql ]; then
  : # placeholder to reflect read_repo_file prisma/migrations/0_init/migration.sql
fi
if [ -f src/routes/auth.ts ]; then
  : # placeholder to reflect read_repo_file src/routes/auth.ts
fi

# Wait for app health endpoint to be ready
wait_for_app_http "http://app:${APP_PORT}/health"

# ---- Case: login_invalid_email_format_400 --------------------------------

# Preconditions: ensure users table is empty
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "TRUNCATE TABLE users RESTART IDENTITY CASCADE;"

# When: perform login with invalid email format
curl -sS -o /tmp/login_invalid_email_format_400.json -w "%{http_code}
" \
  -X POST "http://app:${APP_PORT}/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email": "invalid-email-format", "password": "somePassword123"}' > /tmp/login_invalid_email_format_400.status

# Then: validate HTTP status and response body
status_code=$(cat /tmp/login_invalid_email_format_400.status)
if [ "${status_code}" -ne 400 ]; then
  echo "Expected HTTP 400 for invalid email format, got ${status_code}" >&2
  exit 1
fi

# Assert error key is present and non-empty; no token/user keys expected
jq '.error' /tmp/login_invalid_email_format_400.json >/tmp/login_invalid_email_format_400.error || {
  echo "Response JSON missing error key" >&2
  exit 1
}

error_val=$(cat /tmp/login_invalid_email_format_400.error)
if [ -z "${error_val}" ] || [ "${error_val}" = "null" ]; then
  echo "Expected a non-null validation error message for invalid email format" >&2
  exit 1
fi

# Ensure token and user are not present on validation failure.
if jq -e '.token' /tmp/login_invalid_email_format_400.json >/dev/null 2>&1; then
  echo "Unexpected token field present on invalid email format" >&2
  exit 1
fi

if jq -e '.user' /tmp/login_invalid_email_format_400.json >/dev/null 2>&1; then
  echo "Unexpected user field present on invalid email format" >&2
  exit 1
fi

# ---- Teardown ------------------------------------------------------------
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "TRUNCATE TABLE users RESTART IDENTITY CASCADE;"
rm -f /tmp/login_invalid_email_format_400.json /tmp/login_invalid_email_format_400.status /tmp/login_invalid_email_format_400.error

# Success marker required by runner
echo "CODEVALID_TEST_ASSERTION_OK:login_invalid_email_format_400"
