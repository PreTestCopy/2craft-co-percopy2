#!/usr/bin/env bash
# Case: product_detail_404_for_inactive_product
# GET /products/:id returns 404 with error payload when the product exists but is inactive
set -euo pipefail

source .codevalid/tests/task_9232350707_20260902042618/api/_infra.sh

# ---------------------------------------------------------------------------
# Seed values
# ---------------------------------------------------------------------------
SELLER_USER_ID="a1b2c3d4-0001-0001-0001-000000000001"
SELLER_PROFILE_ID="a1b2c3d4-0002-0002-0002-000000000002"
INACTIVE_PRODUCT_ID="a1b2c3d4-0003-0003-0003-000000000003"

# ---------------------------------------------------------------------------
# Seed SQL
# ---------------------------------------------------------------------------

# 1. Insert a user to act as the seller
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES (
  '$SELLER_USER_ID',
  'inactive-seller@example.com',
  'hashed_password',
  'SELLER',
  'ACTIVE',
  NOW()
)
ON CONFLICT (id) DO NOTHING;
"

# 2. Insert a seller_profile linked to that user
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES (
  '$SELLER_PROFILE_ID',
  '$SELLER_USER_ID',
  'Inactive Test Store',
  'Test bio'
)
ON CONFLICT (id) DO NOTHING;
"

# 3. Insert a product that is visible=false and status='DRAFT' (inactive)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES (
  '$INACTIVE_PRODUCT_ID',
  '$SELLER_PROFILE_ID',
  'Inactive Widget',
  'This product is not active',
  'widgets',
  1999,
  10,
  '{}',
  'DRAFT',
  false,
  NOW()
)
ON CONFLICT (id) DO NOTHING;
"

# ---------------------------------------------------------------------------
# When: GET /products/:id for the inactive product — no auth header
# ---------------------------------------------------------------------------
RESPONSE=$(curl -s -w "
%{http_code}" \
  -H "Accept: application/json" \
  "$APP_URL/products/$INACTIVE_PRODUCT_ID")

BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)

echo "HTTP Status: $STATUS"
echo "Response Body: $BODY"

# ---------------------------------------------------------------------------
# Then: assertions
# ---------------------------------------------------------------------------

# Assert HTTP 404
if [ "$STATUS" -ne 404 ]; then
  echo "FAIL: Expected HTTP 404, got $STATUS"
  exit 1
fi

# Assert response body is valid JSON
echo "$BODY" | jq . > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "FAIL: Response body is not valid JSON"
  exit 1
fi

# Assert error payload is present (key "error" or "message" must exist and be non-empty)
ERROR_FIELD=$(echo "$BODY" | jq -r '.error // .message // empty')
if [ -z "$ERROR_FIELD" ]; then
  echo "FAIL: Expected an error payload with 'error' or 'message' key, got: $BODY"
  exit 1
fi

# Assert product details are NOT leaked in the response
TITLE_LEAK=$(echo "$BODY" | jq -r '.title // empty')
if [ -n "$TITLE_LEAK" ]; then
  echo "FAIL: Product title was unexpectedly returned in 404 response"
  exit 1
fi

echo "PASS: GET /products/$INACTIVE_PRODUCT_ID correctly returned 404 with error payload for inactive product"

# ---------------------------------------------------------------------------
# Teardown
# ---------------------------------------------------------------------------
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
DELETE FROM products WHERE id = '$INACTIVE_PRODUCT_ID';
DELETE FROM seller_profiles WHERE id = '$SELLER_PROFILE_ID';
DELETE FROM users WHERE id = '$SELLER_USER_ID';
" || true

echo "CODEVALID_TEST_ASSERTION_OK:product_detail_404_for_inactive_product"
