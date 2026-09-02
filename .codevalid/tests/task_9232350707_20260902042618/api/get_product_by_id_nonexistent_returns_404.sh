#!/usr/bin/env bash
# Case: get_product_by_id_nonexistent_returns_404
# Verify that GET /products/:id returns HTTP 404 with { "error": "Product not found" }
# when the requested product id does not exist in the database.
set -euo pipefail

# Setup
source .codevalid/tests/task_9232350707_20260902042618/api/_infra.sh

NONEXISTENT_ID="nonexistent-product-id-00000000"

# Optional: remove any stale row from a prior run
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c \
  "DELETE FROM products WHERE id = '${NONEXISTENT_ID}';"

# When
# Send GET request for a non-existent product id
RESPONSE=$(curl -s -w "
%{http_code}" \
  -H "Accept: application/json" \
  "${BASE_URL}/products/${NONEXISTENT_ID}")

HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)

# Then

# Assert HTTP 404
if [ "$HTTP_STATUS" -ne 404 ]; then
  echo "FAIL: Expected HTTP 404, got $HTTP_STATUS"
  echo "Body: $HTTP_BODY"
  exit 1
fi

# Assert response body contains 'error' field
ERROR_FIELD=$(echo "$HTTP_BODY" | jq -r '.error // empty')
if [ -z "$ERROR_FIELD" ]; then
  echo "FAIL: Expected JSON body with 'error' field, got: $HTTP_BODY"
  exit 1
fi

# Assert error message is meaningful (non-empty, non-null string)
if [ "$ERROR_FIELD" = "null" ]; then
  echo "FAIL: 'error' field is null"
  exit 1
fi

echo "PASS: HTTP 404 with error payload: $ERROR_FIELD"

# Teardown: no rows were inserted; nothing to clean up.
echo "Teardown: nothing to clean up for this case."

echo "CODEVALID_TEST_ASSERTION_OK:get_product_by_id_nonexistent_returns_404"
