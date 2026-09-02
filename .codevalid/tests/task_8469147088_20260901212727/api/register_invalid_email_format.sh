#!/usr/bin/env bash
# Case: register_invalid_email_format
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

echo "[register_invalid_email_format] BASE_URL=${BASE_URL}"
echo "[register_invalid_email_format] DATABASE_URL=${DATABASE_URL}"

# ── When: POST /auth/register with invalid email ──────────────────────────────
echo "[register_invalid_email_format] Sending POST ${BASE_URL}/auth/register with malformed email..."
RESPONSE=$(curl -s -o /tmp/reg_invalid_email_body.json -w "%{http_code}" \
  -X POST "${BASE_URL}/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"email":"not-an-email","password":"securepassword","role":"BUYER"}')

echo "[register_invalid_email_format] HTTP status: ${RESPONSE}"
echo "[register_invalid_email_format] Response body:"
cat /tmp/reg_invalid_email_body.json

# ── Then: Assertions ─────────────────────────────────────────────────────────

# 1. Assert HTTP 400
if [ "$RESPONSE" != "400" ]; then
  echo "FAIL: Expected HTTP 400, got $RESPONSE"
  exit 1
fi
echo "[PASS] 1. HTTP status is 400"

# 2. Assert response body contains 'error' key
ERROR_VALUE=$(jq -r '.error // empty' /tmp/reg_invalid_email_body.json)
if [ -z "$ERROR_VALUE" ]; then
  echo "FAIL: Response body missing 'error' key"
  exit 1
fi
echo "[PASS] 2. error key present: $ERROR_VALUE"

# 3. Assert error message mentions invalid/email/format (informational — do not fail)
if echo "$ERROR_VALUE" | grep -qi "invalid\|email\|format"; then
  echo "[PASS] 3. error message mentions invalid email: $ERROR_VALUE"
else
  echo "[WARN] 3. error message present but did not match expected wording: $ERROR_VALUE"
fi

# 4. Assert no user row was created with this value
ROW_COUNT=$(psql "${DATABASE_URL}" -tAc "SELECT COUNT(*) FROM users WHERE email = 'not-an-email';")
if [ "$ROW_COUNT" != "0" ]; then
  echo "FAIL: A user row was unexpectedly created for the malformed email (count=$ROW_COUNT)"
  exit 1
fi
echo "[PASS] 4. No DB row created for malformed email"

echo "[register_invalid_email_format] PASS: HTTP 400 returned, error key present, no DB row created"

# ── Success marker (required by runner) ───────────────────────────────────────
echo "CODEVALID_TEST_ASSERTION_OK:register_invalid_email_format"
