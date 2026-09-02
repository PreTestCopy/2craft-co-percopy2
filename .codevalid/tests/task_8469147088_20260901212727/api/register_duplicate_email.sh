#!/usr/bin/env bash
# Case: register_duplicate_email
# Buyer Account Registration with Validation and Auth Token Issuance
set -euo pipefail

# ── Infra bootstrap ──────────────────────────────────────────────────────────
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Try relative path first (running from /work in container), then fallback
if [ -f "/work/_infra.sh" ]; then
  source /work/_infra.sh
elif [ -f "${SOURCE_DIR}/../../../_infra.sh" ]; then
  source "${SOURCE_DIR}/../../../_infra.sh"
else
  # Inline defaults for container environment
  export BASE_URL="http://app:6713"
  export DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
fi

echo "[register_duplicate_email] BASE_URL=${BASE_URL}"
echo "[register_duplicate_email] DATABASE_URL=${DATABASE_URL}"

# ── Seed: ensure a pre-existing user with this email exists ───────────────────
echo "[register_duplicate_email] Seeding: removing any prior duplicate@example.com record..."
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c \
  "DELETE FROM users WHERE email = 'duplicate@example.com';" || true

echo "[register_duplicate_email] Seeding: inserting existing user row..."
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c \
  "INSERT INTO users (id, email, password_hash, role, status, created_at) \
   VALUES ( \
     'seed-dup-buyer-001', \
     'duplicate@example.com', \
     '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', \
     'BUYER', \
     'ACTIVE', \
     NOW() \
   );"

# Verify seed row exists
SEED_COUNT=$(psql "${DATABASE_URL}" -t -A -c \
  "SELECT COUNT(*) FROM users WHERE email = 'duplicate@example.com';")
if [ "$SEED_COUNT" != "1" ]; then
  echo "FAIL: Seed setup failed — expected 1 row, found $SEED_COUNT"
  exit 1
fi
echo "[register_duplicate_email] Seed row confirmed (count=${SEED_COUNT})"

# ── When: POST /auth/register with duplicate email ────────────────────────────
echo "[register_duplicate_email] Sending POST ${BASE_URL}/auth/register with duplicate email..."
RESPONSE=$(curl -s -w "
%{http_code}" \
  -X POST "${BASE_URL}/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "duplicate@example.com",
    "password": "Password123",
    "role": "BUYER"
  }')

HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)

echo "[register_duplicate_email] HTTP status: ${HTTP_STATUS}"
echo "[register_duplicate_email] HTTP body:   ${HTTP_BODY}"

# ── Then: Assertions ─────────────────────────────────────────────────────────

# 1. HTTP status is 400
if [ "$HTTP_STATUS" != "400" ]; then
  echo "FAIL: Expected HTTP 400, got $HTTP_STATUS"
  echo "Body: $HTTP_BODY"
  exit 1
fi
echo "[PASS] 1. HTTP status is 400"

# 2. Error message indicates email already registered
ERROR_MSG=$(echo "$HTTP_BODY" | jq -r '.error')
if [ "$ERROR_MSG" != "Email already registered" ]; then
  echo "FAIL: Expected error 'Email already registered', got '$ERROR_MSG'"
  exit 1
fi
echo "[PASS] 2. error message = '${ERROR_MSG}'"

# 3. No duplicate row was created — exactly 1 row for this email
USER_COUNT=$(psql "${DATABASE_URL}" -t -A -c \
  "SELECT COUNT(*) FROM users WHERE email = 'duplicate@example.com';")
if [ "$USER_COUNT" != "1" ]; then
  echo "FAIL: Expected exactly 1 user row for duplicate@example.com, found $USER_COUNT"
  exit 1
fi
echo "[PASS] 3. DB user count for duplicate@example.com = ${USER_COUNT} (no duplicate created)"

# ── Teardown ──────────────────────────────────────────────────────────────────
echo "[register_duplicate_email] Teardown: removing seed user..."
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c \
  "DELETE FROM users WHERE email = 'duplicate@example.com';" || true

# ── Success marker (required by runner) ───────────────────────────────────────
echo "CODEVALID_TEST_ASSERTION_OK:register_duplicate_email"
