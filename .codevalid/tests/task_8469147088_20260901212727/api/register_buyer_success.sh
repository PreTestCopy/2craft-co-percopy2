#!/usr/bin/env bash
set -euo pipefail

# ── 0. Bootstrap ────────────────────────────────────────────────────────────
source .codevalid/_infra.sh
# Expected exports: APP_URL, DATABASE_URL, JWT_SECRET

CASE_DIR=".codevalid/mappings/cases/register_buyer_success"
mkdir -p "$CASE_DIR"

EMAIL="buyer_test@example.com"
PASSWORD="SecurePass1"
ROLE="BUYER"

# ── 1. Cleanup / idempotency ────────────────────────────────────────────────
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c \
  "DELETE FROM users WHERE email = '${EMAIL}';"

# ── 2. Call the endpoint (WHEN) ──────────────────────────────────────────────
RESPONSE=$(curl -s -w '
%{http_code}' \
  -X POST "${APP_URL}/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"${ROLE}\"}")

HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)

echo "HTTP Status : $HTTP_STATUS"
echo "HTTP Body   : $HTTP_BODY"

# Persist raw response for debugging
echo "$HTTP_BODY" > "$CASE_DIR/response.json"

# ── 3. Assert HTTP 201 ───────────────────────────────────────────────────────
if [ "$HTTP_STATUS" != "201" ]; then
  echo "FAIL: expected HTTP 201, got $HTTP_STATUS"
  exit 1
fi

# ── 4. Assert response body contains token ──────────────────────────────────
TOKEN=$(echo "$HTTP_BODY" | jq -r '.token // empty')
if [ -z "$TOKEN" ]; then
  echo "FAIL: 'token' field is missing or empty in response"
  exit 1
fi
echo "Token present: ${TOKEN:0:20}..."

# ── 5. Assert user object fields ────────────────────────────────────────────
USER_EMAIL=$(echo "$HTTP_BODY" | jq -r '.user.email // empty')
USER_ROLE=$(echo "$HTTP_BODY" | jq -r '.user.role // empty')
USER_STATUS=$(echo "$HTTP_BODY" | jq -r '.user.status // empty')
USER_SELLER_PROFILE=$(echo "$HTTP_BODY" | jq '.user.sellerProfile')

if [ "$USER_EMAIL" != "$EMAIL" ]; then
  echo "FAIL: user.email expected '$EMAIL', got '$USER_EMAIL'"
  exit 1
fi

if [ "$USER_ROLE" != "BUYER" ]; then
  echo "FAIL: user.role expected 'BUYER', got '$USER_ROLE'"
  exit 1
fi

if [ "$USER_STATUS" != "ACTIVE" ]; then
  echo "FAIL: user.status expected 'ACTIVE', got '$USER_STATUS'"
  exit 1
fi

if [ "$USER_SELLER_PROFILE" != "null" ]; then
  echo "FAIL: user.sellerProfile expected null for BUYER, got '$USER_SELLER_PROFILE'"
  exit 1
fi

# ── 6. Assert database row was created ──────────────────────────────────────
DB_COUNT=$(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -tAc \
  "SELECT COUNT(*) FROM users WHERE email = '${EMAIL}' AND role = 'BUYER' AND status = 'ACTIVE';")

if [ "$DB_COUNT" != "1" ]; then
  echo "FAIL: expected 1 user row in DB, found $DB_COUNT"
  exit 1
fi

echo "PASS: register_buyer_success"
echo "CODEVALID_TEST_ASSERTION_OK:register_buyer_success"

# ── 7. Teardown (optional idempotency) ──────────────────────────────────────
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c \
  "DELETE FROM users WHERE email = '${EMAIL}';"
