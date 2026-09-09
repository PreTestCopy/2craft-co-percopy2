#!/usr/bin/env bash
set -euo pipefail

# Case: login_non_active_status_403

### Setup
source tests/task_6420109326_20260909135419/api/_infra.sh

# Migrations are applied by the app service via MIGRATE_CMD before this script runs.

# Confirm app service port from compose (TG/human: read and verify)
# (Informational only; not required for script execution)
# read_repo_file .codevalid/docker-compose.yml

# Optionally verify app is up (replace /health if app uses a different path)
curl -sS "http://app:${APP_PORT}/health" || true

### Preconditions

# Load Prisma schema and migration definition for reference (human-check)
# (Informational only; not required for script execution)
# read_repo_file prisma/schema.prisma
# read_repo_file prisma/migrations/0_init/migration.sql

# Choose seed values for the non-ACTIVE buyer
buyer_id="buyer-non-active-1"
buyer_email="non.active.buyer@example.com"
buyer_plain_password="BuyerPassword123!"

# NOTE: The plan instructs generating a bcrypt hash via Node separately and pasting here.
# Generate the hash at runtime using bcryptjs (installed in seed-test image at /work/node_modules)
buyer_password_hash=$(node -e "const b=require('bcryptjs');b.hash('${buyer_plain_password}',10).then(h=>process.stdout.write(h))")

# Seed the non-ACTIVE BUYER user into the users table
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES (
  '${buyer_id}',
  '${buyer_email}',
  '${buyer_password_hash}',
  'BUYER',
  'PENDING',
  NOW()
);
" || {
  echo "Failed to insert non-ACTIVE buyer user" >&2
  exit 1
}

### When

# Prepare login request body JSON for the non-ACTIVE buyer
login_body=$(jq -n --arg email "$buyer_email" --arg password "$buyer_plain_password" '{
  email: $email,
  password: $password
}')

# Call POST /auth/login against the running app
http_code=$(mktemp)
response_body=$(curl -sS -w "%{http_code}" -o >(tee /tmp/login_non_active_status_403_response.json) \
  -H "Content-Type: application/json" \
  -d "$login_body" \
  "http://app:${APP_PORT}/auth/login" | tee "$http_code") || {
  echo "curl to /auth/login failed" >&2
  rm -f "$http_code"
  exit 1
}

status_code=$(cat "$http_code")
echo "HTTP status: $status_code"
echo "Response body:"
cat /tmp/login_non_active_status_403_response.json || true

### Then

# Assert that the login was rejected for the non-ACTIVE account
test "$status_code" = "403"

# Ensure no successful login payload is returned:
# - token key must be absent or null
# - user object must be absent or not indicate an authenticated session

# Check that token is not present or is null
jq '.token' /tmp/login_non_active_status_403_response.json || true

# If token exists and is non-null/non-empty, fail the test
token_value=$(jq -r '.token // empty' /tmp/login_non_active_status_403_response.json || true)
if [ -n "$token_value" ]; then
  echo "Expected no JWT token for non-ACTIVE account, but token was present" >&2
  rm -f /tmp/login_non_active_status_403_response.json "$http_code"
  exit 1
fi

# Check if user object is present; if it is, ensure it does not represent a successful authenticated buyer.
# Since schema expects user on success, for a proper 403 rejection we expect either no user or an error-only payload.
user_present=$(jq 'has("user")' /tmp/login_non_active_status_403_response.json || echo "false")
if [ "$user_present" = "true" ]; then
  echo "Expected no authenticated user object for non-ACTIVE account, but user field was present" >&2
  rm -f /tmp/login_non_active_status_403_response.json "$http_code"
  exit 1
fi

# Optionally assert presence of an error message (without relying on its exact text)
jq '.error' /tmp/login_non_active_status_403_response.json || true

### Teardown

# Remove the seeded non-ACTIVE buyer user row
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
DELETE FROM users WHERE id = '${buyer_id}';
" || {
  echo "Failed to delete non-ACTIVE buyer user" >&2
}

# Clean up temporary files
rm -f /tmp/login_non_active_status_403_response.json "$http_code"

# Success marker required by the runner
echo "CODEVALID_TEST_ASSERTION_OK:login_non_active_status_403"
