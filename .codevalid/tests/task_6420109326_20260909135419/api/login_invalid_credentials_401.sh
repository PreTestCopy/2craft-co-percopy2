#!/usr/bin/env bash
set -euo pipefail

# Case: login_invalid_credentials_401

# Setup
source tests/task_6420109326_20260909135419/api/_infra.sh

# Preconditions: clear users table and insert a known ACTIVE BUYER user
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "TRUNCATE TABLE users RESTART IDENTITY CASCADE;"

# Insert an ACTIVE BUYER user with a known password hash for existing_email
# Note: password_hash here is a precomputed bcrypt hash literal for "CorrectPass123!"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES ('00000000-0000-0000-0000-000000000001', 'existing_buyer@example.com', '\$2b\$10\$abcdefghijklmnopqrstuvABCDEFGHijklmnoPQRSTUV', 'BUYER', 'ACTIVE', NOW());"

# When
# 1) Non-existent email with valid format
curl -s -o /tmp/login_nonexistent.json -w "%{http_code}" "http://app:${APP_PORT}/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"missing_user@example.com","password":"AnyPassword123!"}' > /tmp/login_nonexistent_status.txt

# 2) Existing email but wrong password
curl -s -o /tmp/login_wrongpwd.json -w "%{http_code}" "http://app:${APP_PORT}/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"existing_buyer@example.com","password":"WrongPass999!"}' > /tmp/login_wrongpwd_status.txt

# Then
# Assert 401 for non-existent email case
NONEXISTENT_STATUS=$(cat /tmp/login_nonexistent_status.txt)
if [ "$NONEXISTENT_STATUS" != "401" ]; then
  echo "Expected 401 for non-existent email, got: $NONEXISTENT_STATUS" >&2
  exit 1
fi

NONEXISTENT_ERROR=$(jq -r '.error // empty' /tmp/login_nonexistent.json)
if [ "$NONEXISTENT_ERROR" != "Invalid credentials" ]; then
  echo "Expected generic 'Invalid credentials' error for non-existent email, got: $NONEXISTENT_ERROR" >&2
  exit 1
fi

# Assert 401 for wrong password case
WRONGPWD_STATUS=$(cat /tmp/login_wrongpwd_status.txt)
if [ "$WRONGPWD_STATUS" != "401" ]; then
  echo "Expected 401 for wrong password, got: $WRONGPWD_STATUS" >&2
  exit 1
fi

WRONGPWD_ERROR=$(jq -r '.error // empty' /tmp/login_wrongpwd.json)
if [ "$WRONGPWD_ERROR" != "Invalid credentials" ]; then
  echo "Expected generic 'Invalid credentials' error for wrong password, got: $WRONGPWD_ERROR" >&2
  exit 1
fi

# Ensure both error messages are identical and do not include field-specific hints
if [ "$NONEXISTENT_ERROR" != "$WRONGPWD_ERROR" ]; then
  echo "Error messages differ between scenarios: '$NONEXISTENT_ERROR' vs '$WRONGPWD_ERROR'" >&2
  exit 1
fi

# Teardown
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "TRUNCATE TABLE users RESTART IDENTITY CASCADE;"

# Success marker required by runner
echo "CODEVALID_TEST_ASSERTION_OK:login_invalid_credentials_401"
