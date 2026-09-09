#!/usr/bin/env bash
set -euo pipefail

# Setup
source tests/task_7793416183_20260909145416/api/_infra.sh

# APP_PORT is set by _infra.sh via PORT (default 3000, override via environment)
APP_PORT="${PORT}"
export APP_PORT

# Ensure DATABASE_URL is available for psql (from infra or environment)
: "${DATABASE_URL:?DATABASE_URL must be set by _infra.sh or environment}"

# Wait for app health endpoint to be ready
curl -sS --retry 30 --retry-delay 2 --retry-connrefused "http://app:${APP_PORT}/health" > /dev/null

# Preconditions
# Clean users table to avoid interference
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "TRUNCATE TABLE users RESTART IDENTITY CASCADE;"

# Seed an existing BUYER user with a specific email and ACTIVE status
EMAIL_DUP="duplicate_buyer@example.com"
PASSWORD_DUP_HASH="prehashed-password-value"
USER_ID_SEEDED="seed-buyer-1"

# Note: password_hash is an opaque bcrypt hash string; we do not need to match the clear-text password used in the test,
# only ensure a row exists to trigger the duplicate email logic.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('$USER_ID_SEEDED', '$EMAIL_DUP', '$PASSWORD_DUP_HASH', 'BUYER', 'ACTIVE', NOW());
"

# Verify the seed row exists
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
SELECT id, email, role, status
FROM users
WHERE email = '$EMAIL_DUP';
"

# When
# Attempt to register a new BUYER using the same email as the seeded user
REQUEST_BODY=$(jq -n \
  --arg email "$EMAIL_DUP" \
  --arg password "newvalidpassword" \
  --arg role "BUYER" \
  '{email: $email, password: $password, role: $role}')

HTTP_RESPONSE=$(curl -sS -o /tmp/register_dup_body.json -w "%{http_code}" \
  -X POST "http://app:${APP_PORT}/auth/register" \
  -H "Content-Type: application/json" \
  -d "$REQUEST_BODY")

echo "HTTP status: $HTTP_RESPONSE"
cat /tmp/register_dup_body.json

# Then
# Assert HTTP status is 400
test "$HTTP_RESPONSE" -eq 400

# Parse JSON response for error message
ERROR_MSG=$(jq -r '.error // empty' /tmp/register_dup_body.json)
echo "Error message: $ERROR_MSG"

# Assert error message matches expected duplicate email message
test "$ERROR_MSG" = "Email already registered"

# Ensure no additional row was created for the duplicated email (still exactly one row)
ROW_COUNT=$(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -t -A -c "
SELECT COUNT(*) FROM users WHERE email = '$EMAIL_DUP';
")
echo "Row count for duplicated email: $ROW_COUNT"
test "$ROW_COUNT" -eq 1

# Teardown
# Clean up users table after test
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "TRUNCATE TABLE users RESTART IDENTITY CASCADE;"

# Success marker for runner
echo "CODEVALID_TEST_ASSERTION_OK:buyer_register_email_already_in_use"
