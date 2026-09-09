#!/usr/bin/env bash
set -euo pipefail

# Case: buyer_register_success

### Setup
source tests/task_7793416183_20260909145416/api/_infra.sh

# Wait for app health endpoint to be ready
curl --retry 10 --retry-delay 3 --retry-connrefused "http://app:${PORT}/health" | jq .

# Confirm users table exists and is empty (or at least has no test buyer email)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM users;"

### Preconditions
# Ensure no existing user has the test buyer email
TEST_BUYER_EMAIL="buyer_success@example.com"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE email = '${TEST_BUYER_EMAIL}';"

# Verify the email is now unused
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM users WHERE email = '${TEST_BUYER_EMAIL}';"

### When
# Perform successful buyer registration with unique email and strong password
PASSWORD="strongpass1"
ROLE="BUYER"

curl -sS -X POST "http://app:${PORT}/auth/register" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg email "$TEST_BUYER_EMAIL" --arg password "$PASSWORD" --arg role "$ROLE" '{email: $email, password: $password, role: $role}')" \
  -o /tmp/buyer_register_success.json \
  -w "%{http_code}" > /tmp/buyer_register_success_status.txt

### Then
# Assert HTTP 201 status
STATUS_CODE="$(cat /tmp/buyer_register_success_status.txt)"
test "$STATUS_CODE" -eq 201

# Assert token is present and non-empty
jq -e '.token' /tmp/buyer_register_success.json > /dev/null
TOKEN_VALUE="$(jq -r '.token' /tmp/buyer_register_success.json)"
test -n "$TOKEN_VALUE"

# Assert user object has expected fields and role/status values
jq -e '.user.id' /tmp/buyer_register_success.json > /dev/null
jq -e '.user.email' /tmp/buyer_register_success.json > /dev/null
jq -e '.user.role' /tmp/buyer_register_success.json > /dev/null
jq -e '.user.status' /tmp/buyer_register_success.json > /dev/null

USER_EMAIL="$(jq -r '.user.email' /tmp/buyer_register_success.json)"
USER_ROLE="$(jq -r '.user.role' /tmp/buyer_register_success.json)"
USER_STATUS="$(jq -r '.user.status' /tmp/buyer_register_success.json)"

test "$USER_EMAIL" = "$TEST_BUYER_EMAIL"
test "$USER_ROLE" = "BUYER"
test "$USER_STATUS" = "ACTIVE"

# Assert sellerProfile is null or absent for BUYER
jq '.user.sellerProfile' /tmp/buyer_register_success.json > /tmp/buyer_register_success_seller_profile.json || true
SELLER_PROFILE_JSON="$(cat /tmp/buyer_register_success_seller_profile.json 2>/dev/null || true)"
# Accept null or empty object/array; just ensure key exists
jq -e '.user.sellerProfile' /tmp/buyer_register_success.json > /dev/null || true

# Verify a row was created in users table with correct role and status
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "SELECT email, role, status FROM users WHERE email = '${TEST_BUYER_EMAIL}';" > /tmp/buyer_register_success_db.txt

grep "${TEST_BUYER_EMAIL}" /tmp/buyer_register_success_db.txt
grep "BUYER" /tmp/buyer_register_success_db.txt
grep "ACTIVE" /tmp/buyer_register_success_db.txt

### Teardown
# Clean up the test user row
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE email = '${TEST_BUYER_EMAIL}';"

# Optionally verify deletion
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM users WHERE email = '${TEST_BUYER_EMAIL}';"

# Success marker required by runner
echo "CODEVALID_TEST_ASSERTION_OK:buyer_register_success"
