#!/usr/bin/env bash
# Case: catalog_listing_empty_array_when_no_active_products
# Verify GET /products returns HTTP 200 with an empty array when no active+visible products exist.
set -euo pipefail

source "$(dirname "$0")/_infra.sh"

echo "=== Case: catalog_listing_empty_array_when_no_active_products ==="

# ---- Step 1: Clean slate ----
echo "[Step 1] Cleaning up any prior test data..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  DELETE FROM products WHERE id IN ('prod-removed-001','prod-hidden-001');
  DELETE FROM seller_profiles WHERE id = 'sp-empty-cat-001';
  DELETE FROM users WHERE id = 'user-empty-cat-001';
"
echo "[Step 1] Done."

# ---- Step 2a: Insert seller user ----
echo "[Step 2a] Inserting seller user..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO users (id, email, password_hash, role, status, created_at)
  VALUES (
    'user-empty-cat-001',
    'seed_empty_catalog_seller@example.com',
    'hashed_pw',
    'SELLER',
    'ACTIVE',
    NOW()
  )
  ON CONFLICT (id) DO NOTHING;
"
echo "[Step 2a] Done."

# ---- Step 2b: Insert seller profile ----
echo "[Step 2b] Inserting seller profile..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO seller_profiles (id, user_id, store_name, bio)
  VALUES (
    'sp-empty-cat-001',
    'user-empty-cat-001',
    'Ghost Store',
    'No active products here'
  )
  ON CONFLICT (id) DO NOTHING;
"
echo "[Step 2b] Done."

# ---- Step 2c: Insert REMOVED product (status=REMOVED, visible=true) — must NOT appear ----
echo "[Step 2c] Inserting REMOVED product..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
  VALUES (
    'prod-removed-001',
    'sp-empty-cat-001',
    'Removed Product',
    'This product has been removed',
    'CRAFTS',
    1000,
    5,
    '{}',
    'REMOVED',
    true,
    NOW()
  )
  ON CONFLICT (id) DO NOTHING;
"
echo "[Step 2c] Done."

# ---- Step 2d: Insert invisible product (status=ACTIVE, visible=false) — must NOT appear ----
echo "[Step 2d] Inserting invisible product..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
  VALUES (
    'prod-hidden-001',
    'sp-empty-cat-001',
    'Hidden Product',
    'This product is not visible',
    'CRAFTS',
    2000,
    3,
    '{}',
    'ACTIVE',
    false,
    NOW()
  )
  ON CONFLICT (id) DO NOTHING;
"
echo "[Step 2d] Done."

# ---- Step 3: Call GET /products (no auth, no query params) ----
echo "[Step 3] Calling GET $APP_URL/products ..."
RESPONSE=$(curl -s -w "
%{http_code}" \
  -H "Accept: application/json" \
  "${APP_URL}/products")

HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)

echo "Status: $HTTP_STATUS"
echo "Body: $HTTP_BODY"

# ---- Step 4: Assert HTTP 200 ----
echo "[Step 4] Asserting HTTP 200..."
if [ "$HTTP_STATUS" != "200" ]; then
  echo "FAIL: Expected HTTP 200, got $HTTP_STATUS"
  echo "Body: $HTTP_BODY"
  exit 1
fi
echo "PASS: HTTP 200"

# ---- Step 5: Assert response is a JSON array ----
echo "[Step 5] Asserting response is a JSON array..."
IS_ARRAY=$(echo "$HTTP_BODY" | jq 'type == "array"')
if [ "$IS_ARRAY" != "true" ]; then
  echo "FAIL: Response body is not a JSON array"
  echo "Body: $HTTP_BODY"
  exit 1
fi
echo "PASS: Response is a JSON array"

# ---- Step 6: Assert array is empty ----
echo "[Step 6] Asserting array length is 0..."
ARRAY_LENGTH=$(echo "$HTTP_BODY" | jq 'length')
if [ "$ARRAY_LENGTH" != "0" ]; then
  echo "FAIL: Expected empty array, got array with $ARRAY_LENGTH element(s)"
  echo "Body: $HTTP_BODY"
  exit 1
fi
echo "PASS: Response is an empty array []"

# ---- Step 7: Cleanup ----
echo "[Step 7] Cleaning up test data..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  DELETE FROM products WHERE id IN ('prod-removed-001','prod-hidden-001');
  DELETE FROM seller_profiles WHERE id = 'sp-empty-cat-001';
  DELETE FROM users WHERE id = 'user-empty-cat-001';
"
echo "[Step 7] Cleanup complete."

echo "PASS: GET /products returned HTTP 200 with empty array []"
echo "CODEVALID_TEST_ASSERTION_OK:catalog_listing_empty_array_when_no_active_products"
