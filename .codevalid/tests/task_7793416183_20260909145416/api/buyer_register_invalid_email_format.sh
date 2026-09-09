#!/usr/bin/env bash
set -euo pipefail

# Case: buyer_register_invalid_email_format

# Setup
source tests/task_7793416183_20260909145416/api/_infra.sh

# Ensure app port is available from compose (informational; no assertion)
read_repo_file .codevalid/docker-compose.yml >/dev/null 2>&1 || true

# Wait for app health endpoint to be ready (assumes GET /health)
ATTEMPTS=30
SLEEP_SECONDS=2
READY=0
for i in $(seq 1 "$ATTEMPTS"); do
  if curl -sS "http://app:${PORT}/health" | jq . >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep "$SLEEP_SECONDS"
done

if [ "$READY" -ne 1 ]; then
  echo "App health endpoint did not become ready on port ${PORT}" >&2
  exit 1
fi

# Preconditions
INVALID_EMAIL="invalid-email-format"  # missing '@' and domain to trigger Zod email validation

# Confirm schema and enums for users table (informational checks)
read_repo_file prisma/schema.prisma >/dev/null 2>&1 || true
read_repo_file prisma/migrations/0_init/migration.sql >/dev/null 2>&1 || true

# Ensure no user exists with the invalid email we'll test
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE email = '$INVALID_EMAIL';"

# When
# Prepare request payload with invalid email, strong password, and BUYER role
REQUEST_BODY=$(jq -n \
  --arg email "$INVALID_EMAIL" \
  --arg password "strongpass123" \
  --arg role "BUYER" \
  '{email: $email, password: $password, role: $role}')

# Send POST /auth/register with invalid email format
HTTP_RESPONSE=$(curl -sS -w "
%{http_code}" -X POST "http://app:${PORT}/auth/register" \
  -H "Content-Type: application/json" \
  -d "$REQUEST_BODY")

# Split body and status code
HTTP_BODY=$(echo "$HTTP_RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tail -n 1)

echo "Status: $HTTP_STATUS"
echo "Body: $HTTP_BODY"

# Then
# Assert HTTP status is 400
test "$HTTP_STATUS" -eq 400

# Assert error field exists and mentions email/invalid format (Zod error)
ERROR_MESSAGE=$(echo "$HTTP_BODY" | jq -r '.error // empty')
test -n "$ERROR_MESSAGE"

echo "$ERROR_MESSAGE" | grep -i "email" >/dev/null

# Confirm no user was created with the invalid email
USER_COUNT=$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM users WHERE email = '$INVALID_EMAIL';")
test "$USER_COUNT" -eq 0

# Teardown
# Clean up any leftover rows with the invalid email (defensive)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE email = '$INVALID_EMAIL';"

# Success marker required by runner
echo "CODEVALID_TEST_ASSERTION_OK:buyer_register_invalid_email_format"
