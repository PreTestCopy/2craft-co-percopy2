#!/usr/bin/env bash
# Case: register_password_too_short
# Buyer Account Registration with Validation and Auth Token Issuance
set -euo pipefail

# ── Infra bootstrap ──────────────────────────────────────────────────────────
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "/work/_infra.sh" ]; then
  source /work/_infra.sh
elif [ -f "${SOURCE_DIR}/../../../_infra.sh" ]; then
  source "${SOURCE_DIR}/../../../_infra.sh"
else
  export BASE_URL="http://app:6713"
  export DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
fi

echo "[register_password_too_short] BASE_URL=${BASE_URL}"
echo "[register_password_too_short] DATABASE_URL=${DATABASE_URL}"

# ── Mapping files ────────────────────────────────────────────────────────────
CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mappings/cases/register_password_too_short"
REQUEST_BODY_FILE="${CASE_DIR}/request.json"
EXPECTED_FRAGMENT_FILE="${CASE_DIR}/expected_error_fragment.txt"

# ── Pre-condition: no existing row for buyer@example.com ─────────────────────
PRE_COUNT=$(psql "${DATABASE_URL}" -tAc "SELECT COUNT(*) FROM users WHERE email = 'buyer@example.com';")
if [ "$PRE_COUNT" != "0" ]; then
  echo "[register_password_too_short] Pre-cleaning existing row for buyer@example.com"
  psql "${DATABASE_URL}" -c "DELETE FROM users WHERE email = 'buyer@example.com';" || true
fi
echo "[register_password_too_short] Pre-condition OK: 0 rows for buyer@example.com"

# ── When: POST /auth/register with short password ────────────────────────────
echo "[register_password_too_short] Sending POST ${BASE_URL}/auth/register with password too short..."
RESPONSE=$(curl -s -o /tmp/reg_pw_too_short_body.json -w "%{http_code}" \
  -X POST "${BASE_URL}/auth/register" \
  -H "Content-Type: application/json" \
  -d @"${REQUEST_BODY_FILE}")

echo "[register_password_too_short] HTTP status: ${RESPONSE}"
echo "[register_password_too_short] Response body:"
cat /tmp/reg_pw_too_short_body.json

# ── Then: Assertions ─────────────────────────────────────────────────────────

# 5a. HTTP status must be 400
if [ "$RESPONSE" != "400" ]; then
  echo "FAIL: Expected HTTP 400, got $RESPONSE"
  echo "Response body: $(cat /tmp/reg_pw_too_short_body.json)"
  exit 1
fi
echo "[PASS] 5a. HTTP status is 400"

# 5b. Response body must contain an 'error' field
ERROR_FIELD=$(jq -r '.error // empty' /tmp/reg_pw_too_short_body.json)
if [ -z "$ERROR_FIELD" ]; then
  echo "FAIL: response JSON has no 'error' field. Body: $(cat /tmp/reg_pw_too_short_body.json)"
  exit 1
fi
echo "[PASS] 5b. 'error' field present: $ERROR_FIELD"

# 5c. Error message must reference password length / 8 characters
EXPECTED_FRAGMENT=$(cat "${EXPECTED_FRAGMENT_FILE}" | tr -d '
')
if echo "$ERROR_FIELD" | grep -qi "$EXPECTED_FRAGMENT"; then
  echo "[PASS] 5c. error message references password length requirement"
else
  echo "FAIL: error message '$ERROR_FIELD' does not contain expected fragment '$EXPECTED_FRAGMENT'"
  exit 1
fi

# 5d. No user row must have been inserted
ROW_COUNT=$(psql "${DATABASE_URL}" -tAc "SELECT COUNT(*) FROM users WHERE email = 'buyer@example.com';")
if [ "$ROW_COUNT" != "0" ]; then
  echo "FAIL: expected 0 rows for buyer@example.com, found $ROW_COUNT"
  exit 1
fi
echo "[PASS] 5d. No user row created for buyer@example.com"

# ── Cleanup (idempotent) ─────────────────────────────────────────────────────
psql "${DATABASE_URL}" -c "DELETE FROM users WHERE email = 'buyer@example.com';" || true

echo "[register_password_too_short] All assertions passed."

# ── Success marker (required by runner) ───────────────────────────────────────
echo "CODEVALID_TEST_ASSERTION_OK:register_password_too_short"
