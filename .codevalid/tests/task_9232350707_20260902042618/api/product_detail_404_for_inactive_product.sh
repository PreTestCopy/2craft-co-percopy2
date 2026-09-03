#!/usr/bin/env bash
# Case: product_detail_404_for_inactive_product
# GET /products/:id returns 404 with error payload when product exists but is inactive (visible=false)
set -euo pipefail

source tests/task_9232350707_20260902042618/api/_infra.sh

CASE_ID="product_detail_404_for_inactive_product"

# ---------------------------------------------------------------------------
# Seed: fixed UUIDs to avoid cross-test collisions
# ---------------------------------------------------------------------------
SELLER_USER_ID="b2c3d4e5-0011-0011-0011-000000000011"
SELLER_PROFILE_ID="b2c3d4e5-0012-0012-0012-000000000012"
INACTIVE_PRODUCT_ID="b2c3d4e5-0013-0013-0013-000000000013"

# 1. Insert seller user
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES (
  '$SELLER_USER_ID',
  'inactive-prod-seller@example.com',
  'hashed_password',
  'SELLER',
  'ACTIVE',
  NOW()
)
ON CONFLICT (id) DO NOTHING;
"

# 2. Insert seller profile
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

# 3. Insert product with visible=false and status='SOLD_OUT'
#    visible=false triggers the non-admin filter (visible: true) → findFirst returns null → 404
#    status='SOLD_OUT' is a valid ProductStatus enum value (ACTIVE | SOLD_OUT | REMOVED)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES (
  '$INACTIVE_PRODUCT_ID',
  '$SELLER_PROFILE_ID',
  'Inactive Widget',
  'This product is not visible to buyers',
  'ART',
  1500,
  0,
  '{}',
  'SOLD_OUT',
  false,
  NOW()
)
ON CONFLICT (id) DO NOTHING;
"

# ---------------------------------------------------------------------------
# When: unauthenticated GET /products/:id for the invisible/inactive product
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
# Then: assert HTTP 404
# ---------------------------------------------------------------------------
if [ "$STATUS" -ne 404 ]; then
  echo "FAIL [$CASE_ID]: Expected HTTP 404, got $STATUS"
  echo "Body: $BODY"
  exit 1
fi

# ---------------------------------------------------------------------------
# Then: response body is valid JSON
# ---------------------------------------------------------------------------
if ! echo "$BODY" | jq . > /dev/null 2>&1; then
  echo "FAIL [$CASE_ID]: Response body is not valid JSON: $BODY"
  exit 1
fi

# ---------------------------------------------------------------------------
# Then: response body contains 'error' or 'message' field (non-empty)
# ---------------------------------------------------------------------------
ERROR_FIELD=$(echo "$BODY" | jq -r '.error // .message // empty')
if [ -z "$ERROR_FIELD" ]; then
  echo "FAIL [$CASE_ID]: Expected error payload with 'error' or 'message' field, got: $BODY"
  exit 1
fi

# ---------------------------------------------------------------------------
# Then: product data is NOT leaked in the 404 response
# ---------------------------------------------------------------------------
TITLE_LEAK=$(echo "$BODY" | jq -r '.title // empty')
if [ -n "$TITLE_LEAK" ]; then
  echo "FAIL [$CASE_ID]: Product title was unexpectedly returned in 404 response"
  exit 1
fi

echo "PASS [$CASE_ID]: HTTP 404 with error payload '$ERROR_FIELD' — inactive product correctly hidden"

# ---------------------------------------------------------------------------
# Teardown
# ---------------------------------------------------------------------------
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
DELETE FROM products WHERE id = '$INACTIVE_PRODUCT_ID';
DELETE FROM seller_profiles WHERE id = '$SELLER_PROFILE_ID';
DELETE FROM users WHERE id = '$SELLER_USER_ID';
" || true

echo "CODEVALID_TEST_ASSERTION_OK:product_detail_404_for_inactive_product"
