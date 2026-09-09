#!/usr/bin/env bash
set -euo pipefail

# Setup
source tests/task_6420109326_20260909135419/api/_infra.sh

# Ensure DATABASE_URL is set and points to toxiproxy Postgres
echo "Using DATABASE_URL=${DATABASE_URL:-}"
if [ -z "${DATABASE_URL:-}" ]; then
  echo "DATABASE_URL is not set"
  exit 1
fi

# Optionally inspect Prisma schema and migration if debugging
read_repo_file prisma/schema.prisma || true
read_repo_file prisma/migrations/0_init/migration.sql || true

# Preconditions
TEST_USER_ID="buyer-login-active-1"
TEST_USER_EMAIL="active.buyer@example.com"
TEST_USER_PASSWORD="PlaintextP@ssw0rd"

# Generate a bcrypt hash for the known password using Node + bcrypt
export TEST_USER_PASSWORD
HASHED_PASSWORD=$(node - <<'EOF'
const bcrypt = require('bcryptjs');
const password = process.env.TEST_USER_PASSWORD || "PlaintextP@ssw0rd";
bcrypt.hash(password, 10).then(hash => {
  console.log(hash);
}).catch(err => {
  console.error(err);
  process.exit(1);
});
EOF
)

if [ -z "$HASHED_PASSWORD" ]; then
  echo "Failed to generate bcrypt hash"
  exit 1
fi

echo "Generated bcrypt hash: $HASHED_PASSWORD"

# Seed the ACTIVE BUYER user into the users table
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES (
  '$TEST_USER_ID',
  '$TEST_USER_EMAIL',
  '$HASHED_PASSWORD',
  'BUYER',
  'ACTIVE',
  NOW()
);
" || {
  echo "Failed to insert test user into users table"
  exit 1
}

# When
LOGIN_RESPONSE="$(
  curl -sS -X POST "http://app:${PORT}/auth/login" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg email "$TEST_USER_EMAIL" --arg password "$TEST_USER_PASSWORD" '{email: $email, password: $password}')" \
    -w "
%{http_code}"
)"

# Split body and status code
LOGIN_BODY="$(printf "%s" "$LOGIN_RESPONSE" | sed '$d')"
LOGIN_STATUS="$(printf "%s" "$LOGIN_RESPONSE" | tail -n1)"

echo "Login status: $LOGIN_STATUS"
echo "Login body: $LOGIN_BODY"

# Then
# Assert HTTP 200
if [ "$LOGIN_STATUS" != "200" ]; then
  echo "Expected HTTP 200 for successful login, got $LOGIN_STATUS"
  # Teardown even on failure
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '$TEST_USER_ID';" || true
  exit 1
fi

# Assert token field is present and non-empty
TOKEN_VALUE="$(echo "$LOGIN_BODY" | jq -r '.token // empty')"
if [ -z "$TOKEN_VALUE" ] || [ "$TOKEN_VALUE" = "null" ]; then
  echo "Expected non-empty token in response, got: $TOKEN_VALUE"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '$TEST_USER_ID';" || true
  exit 1
fi

# Assert user object exists
USER_EXISTS="$(echo "$LOGIN_BODY" | jq 'has("user")')"
if [ "$USER_EXISTS" != "true" ]; then
  echo "Expected user object in response"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '$TEST_USER_ID';" || true
  exit 1
fi

# Assert user.id is present and matches seeded id
RESP_USER_ID="$(echo "$LOGIN_BODY" | jq -r '.user.id // empty')"
if [ "$RESP_USER_ID" != "$TEST_USER_ID" ]; then
  echo "Expected user.id=$TEST_USER_ID, got $RESP_USER_ID"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '$TEST_USER_ID';" || true
  exit 1
fi

# Assert user.email matches seeded email
RESP_USER_EMAIL="$(echo "$LOGIN_BODY" | jq -r '.user.email // empty')"
if [ "$RESP_USER_EMAIL" != "$TEST_USER_EMAIL" ]; then
  echo "Expected user.email=$TEST_USER_EMAIL, got $RESP_USER_EMAIL"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '$TEST_USER_ID';" || true
  exit 1
fi

# Assert user.role is BUYER
RESP_USER_ROLE="$(echo "$LOGIN_BODY" | jq -r '.user.role // empty')"
if [ "$RESP_USER_ROLE" != "BUYER" ]; then
  echo "Expected user.role=BUYER, got $RESP_USER_ROLE"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '$TEST_USER_ID';" || true
  exit 1
fi

# Assert user.status is ACTIVE
RESP_USER_STATUS="$(echo "$LOGIN_BODY" | jq -r '.user.status // empty')"
if [ "$RESP_USER_STATUS" != "ACTIVE" ]; then
  echo "Expected user.status=ACTIVE, got $RESP_USER_STATUS"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '$TEST_USER_ID';" || true
  exit 1
fi

# Teardown
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
DELETE FROM users
WHERE id = '$TEST_USER_ID';
" || {
  echo "Failed to delete test user from users table"
  exit 1
}

# Success marker required by runner
echo "CODEVALID_TEST_ASSERTION_OK:login_active_buyer_success"
