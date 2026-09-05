#!/usr/bin/env bash
# Case: register_buyer_success
# Buyer Account Registration, Validation, and Login Authentication with Auth Token Issuance
set -euo pipefail

# ── Infra bootstrap ──────────────────────────────────────────────────────────
source tests/task_8469147088_20260901212727/api/_infra.sh

echo "[register_buyer_success] APP_BASE_URL=${APP_BASE_URL}"
echo "[register_buyer_success] DATABASE_URL=${DATABASE_URL}"

# ── Given: no user with email buyer_new@example.com exists ───────────────────
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c \
  "DELETE FROM users WHERE email = 'buyer_new@example.com';"

# ── When: POST /auth/register with valid email, password >= 8 chars, role = BUYER
RESPONSE=$(curl -s -w "
%{http_code}" \
  -X POST "${APP_BASE_URL}/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"email":"buyer_new@example.com","password":"SecurePass1","role":"BUYER"}')

HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)

echo "[register_buyer_success] HTTP status: ${HTTP_STATUS}"
echo "[register_buyer_success] HTTP body:   ${HTTP_BODY}"

# ── Then: HTTP 201 ────────────────────────────────────────────────────────────
echo "=== register_buyer_success: status check ==="
[ "$HTTP_STATUS" = "201" ] || { echo "FAIL: expected 201, got $HTTP_STATUS — body: $HTTP_BODY"; exit 1; }
echo "PASS: status 201"

# Then: response body contains non-empty token
TOKEN=$(echo "$HTTP_BODY" | jq -r '.token // empty')
[ -n "$TOKEN" ] || { echo "FAIL: token is missing or empty — body: $HTTP_BODY"; exit 1; }
echo "PASS: token present"

# Then: user.email = buyer_new@example.com
USER_EMAIL=$(echo "$HTTP_BODY" | jq -r '.user.email // empty')
[ "$USER_EMAIL" = "buyer_new@example.com" ] || { echo "FAIL: user.email expected 'buyer_new@example.com', got '$USER_EMAIL'"; exit 1; }
echo "PASS: user.email correct"

# Then: user.role = BUYER
USER_ROLE=$(echo "$HTTP_BODY" | jq -r '.user.role // empty')
[ "$USER_ROLE" = "BUYER" ] || { echo "FAIL: user.role expected 'BUYER', got '$USER_ROLE'"; exit 1; }
echo "PASS: user.role = BUYER"

# Then: user.status = ACTIVE
USER_STATUS=$(echo "$HTTP_BODY" | jq -r '.user.status // empty')
[ "$USER_STATUS" = "ACTIVE" ] || { echo "FAIL: user.status expected 'ACTIVE', got '$USER_STATUS'"; exit 1; }
echo "PASS: user.status = ACTIVE"

# Then: user.id is non-empty
USER_ID=$(echo "$HTTP_BODY" | jq -r '.user.id // empty')
[ -n "$USER_ID" ] || { echo "FAIL: user.id is missing or empty — body: $HTTP_BODY"; exit 1; }
echo "PASS: user.id present"

# Verify row persisted in DB with correct role and status
DB_ROW=$(psql "$DATABASE_URL" -t -A -F'|' -v ON_ERROR_STOP=1 \
  -c "SELECT role, status FROM users WHERE email = 'buyer_new@example.com' LIMIT 1;")
DB_ROLE=$(echo "$DB_ROW" | cut -d'|' -f1)
DB_STATUS=$(echo "$DB_ROW" | cut -d'|' -f2)
[ "$DB_ROLE" = "BUYER" ] || { echo "FAIL: DB role expected 'BUYER', got '$DB_ROLE'"; exit 1; }
[ "$DB_STATUS" = "ACTIVE" ] || { echo "FAIL: DB status expected 'ACTIVE', got '$DB_STATUS'"; exit 1; }
echo "PASS: DB row persisted with role=BUYER status=ACTIVE"

echo "=== register_buyer_success: ALL CHECKS PASSED ==="
echo "CODEVALID_TEST_ASSERTION_OK:register_buyer_success"
