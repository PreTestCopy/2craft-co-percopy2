#!/usr/bin/env bash
# Case: product_detail_404_for_nonexistent_id
# Verify that GET /products/:id returns HTTP 404 with a clear error payload
# when the requested product id does not exist in the database.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_infra.sh
source "${SCRIPT_DIR}/_infra.sh"

# ---------------------------------------------------------------------------
# Seed: truncate products to ensure clean state
# ---------------------------------------------------------------------------
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "TRUNCATE products CASCADE;" \
  || { echo "WARN: TRUNCATE failed (table may not exist yet), continuing..."; }

# ---------------------------------------------------------------------------
# When: request a product with the nil UUID (guaranteed non-existent)
# ---------------------------------------------------------------------------
RESPONSE=$(curl -s -w "
%{http_code}" \
  "${APP_URL}/products/00000000-0000-0000-0000-000000000000")

HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)

# ---------------------------------------------------------------------------
# Then: assertions
# ---------------------------------------------------------------------------

# 1. Assert HTTP 404 status
[ "$HTTP_STATUS" -eq 404 ] || {
  echo "FAIL: expected 404, got $HTTP_STATUS"
  echo "Body: $HTTP_BODY"
  exit 1
}

# 2. Assert response body is valid JSON
echo "$HTTP_BODY" | jq . > /dev/null 2>&1 || {
  echo "FAIL: response body is not valid JSON"
  echo "Body: $HTTP_BODY"
  exit 1
}

# 3. Assert error payload contains a non-empty 'error' or 'message' field
ERROR_FIELD=$(echo "$HTTP_BODY" | jq -r '.error // .message // empty')
[ -n "$ERROR_FIELD" ] || {
  echo "FAIL: expected a non-empty 'error' or 'message' field in the response body"
  echo "Body: $HTTP_BODY"
  exit 1
}

echo "PASS: product_detail_404_for_nonexistent_id"

# ---------------------------------------------------------------------------
# Teardown (optional)
# ---------------------------------------------------------------------------
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "TRUNCATE products CASCADE;" \
  || true

echo "CODEVALID_TEST_ASSERTION_OK:product_detail_404_for_nonexistent_id"
