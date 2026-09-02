#!/usr/bin/env bash
# Case: register_buyer_success
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

echo "[register_buyer_success] BASE_URL=${BASE_URL}"
echo "[register_buyer_success] DATABASE_URL=${DATABASE_URL}"

# ── Seed: clean up any prior record ──────────────────────────────────────────
echo "[register_buyer_success] Seeding: removing any prior buyer_new@example.com record..."
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c \
  "DELETE FROM users WHERE email = 'buyer_new@example.com';" || true

# ── When: POST /auth/register ─────────────────────────────────────────────────
echo "[register_buyer_success] Sending POST ${BASE_URL}/auth/register ..."
RESPONSE=$(curl -s -w "
%{http_code}" \
  -X POST "${BASE_URL}/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "buyer_new@example.com",
    "password": "Passw0rd!",
    "role": "BUYER"
  }')

HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)

echo "[register_buyer_success] HTTP status: ${HTTP_STATUS}"
echo "[register_buyer_success] HTTP body:   ${HTTP_BODY}"

# ── Then: Assertions ─────────────────────────────────────────────────────────

# 1. Status code is 201
[ "$HTTP_STATUS" = "201" ] || { echo "FAIL: expected HTTP 201, got $HTTP_STATUS"; exit 1; }
echo "[PASS] 1. HTTP status is 201"

# 2. Response body contains a non-empty token
TOKEN=$(echo "$HTTP_BODY" | jq -r '.token')
[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || { echo "FAIL: token missing or null"; exit 1; }
echo "[PASS] 2. token field is present and non-empty"

# 3. user.email matches submitted email
USER_EMAIL=$(echo "$HTTP_BODY" | jq -r '.user.email')
[ "$USER_EMAIL" = "buyer_new@example.com" ] || { echo "FAIL: user.email = $USER_EMAIL"; exit 1; }
echo "[PASS] 3. user.email = ${USER_EMAIL}"

# 4. user.role is BUYER
USER_ROLE=$(echo "$HTTP_BODY" | jq -r '.user.role')
[ "$USER_ROLE" = "BUYER" ] || { echo "FAIL: user.role = $USER_ROLE"; exit 1; }
echo "[PASS] 4. user.role = ${USER_ROLE}"

# 5. user.status is ACTIVE (not PENDING)
USER_STATUS=$(echo "$HTTP_BODY" | jq -r '.user.status')
[ "$USER_STATUS" = "ACTIVE" ] || { echo "FAIL: user.status = $USER_STATUS"; exit 1; }
echo "[PASS] 5. user.status = ${USER_STATUS}"

# 6. user.id is a non-empty string
USER_ID=$(echo "$HTTP_BODY" | jq -r '.user.id')
[ -n "$USER_ID" ] && [ "$USER_ID" != "null" ] || { echo "FAIL: user.id missing"; exit 1; }
echo "[PASS] 6. user.id = ${USER_ID}"

# 7. user.sellerProfile is null (BUYER has no seller profile)
SELLER_PROFILE=$(echo "$HTTP_BODY" | jq '.user.sellerProfile')
[ "$SELLER_PROFILE" = "null" ] || { echo "FAIL: sellerProfile should be null, got $SELLER_PROFILE"; exit 1; }
echo "[PASS] 7. user.sellerProfile is null"

# 8. Row persisted in DB with correct values
DB_ROLE=$(psql "${DATABASE_URL}" -t -A -c \
  "SELECT role FROM users WHERE email = 'buyer_new@example.com';")
[ "$DB_ROLE" = "BUYER" ] || { echo "FAIL: DB role = $DB_ROLE"; exit 1; }
echo "[PASS] 8a. DB role = ${DB_ROLE}"

DB_STATUS=$(psql "${DATABASE_URL}" -t -A -c \
  "SELECT status FROM users WHERE email = 'buyer_new@example.com';")
[ "$DB_STATUS" = "ACTIVE" ] || { echo "FAIL: DB status = $DB_STATUS"; exit 1; }
echo "[PASS] 8b. DB status = ${DB_STATUS}"

DB_HASH=$(psql "${DATABASE_URL}" -t -A -c \
  "SELECT password_hash FROM users WHERE email = 'buyer_new@example.com';")
[ "$DB_HASH" != "Passw0rd!" ] || { echo "FAIL: password stored in plain text"; exit 1; }
[ -n "$DB_HASH" ] || { echo "FAIL: password_hash is empty"; exit 1; }
echo "[PASS] 8c. password_hash is a non-empty hash (not plain text)"

# 9. JWT decodes to matching claims (structural check — no signature verification needed)
JWT_SEGMENT=$(echo "$TOKEN" | cut -d. -f2)
# Add base64url padding
JWT_PADDED=$(echo "$JWT_SEGMENT" | awk '{
  n = length($0) % 4
  if (n == 2) $0 = $0 "=="
  else if (n == 3) $0 = $0 "="
  print
}')
# Replace base64url chars with standard base64
JWT_B64=$(echo "$JWT_PADDED" | tr '_-' '/+')
JWT_PAYLOAD=$(echo "$JWT_B64" | base64 -d 2>/dev/null)

JWT_EMAIL=$(echo "$JWT_PAYLOAD" | jq -r '.email')
JWT_ROLE=$(echo "$JWT_PAYLOAD" | jq -r '.role')

[ "$JWT_EMAIL" = "buyer_new@example.com" ] || { echo "FAIL: JWT email = $JWT_EMAIL"; exit 1; }
echo "[PASS] 9a. JWT email = ${JWT_EMAIL}"

[ "$JWT_ROLE" = "BUYER" ] || { echo "FAIL: JWT role = $JWT_ROLE"; exit 1; }
echo "[PASS] 9b. JWT role = ${JWT_ROLE}"

# ── Teardown ──────────────────────────────────────────────────────────────────
echo "[register_buyer_success] Teardown: removing test user..."
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c \
  "DELETE FROM users WHERE email = 'buyer_new@example.com';" || true

# ── Success marker (required by runner) ───────────────────────────────────────
echo "CODEVALID_TEST_ASSERTION_OK:register_buyer_success"
