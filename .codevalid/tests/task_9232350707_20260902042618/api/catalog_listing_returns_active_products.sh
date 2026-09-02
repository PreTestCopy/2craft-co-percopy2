#!/usr/bin/env bash
# Case: catalog_listing_returns_active_products
# Verify GET /products returns HTTP 200 with active products array including required fields.
set -euo pipefail

source "$(dirname "$0")/_infra.sh"

echo "=== Case: catalog_listing_returns_active_products ==="

# ---- Step 1: Clean slate ----
echo "[Step 1] Cleaning up any prior test data..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  DELETE FROM products        WHERE id IN ('c0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000099');
  DELETE FROM seller_profiles WHERE id = 'b0000000-0000-0000-0000-000000000001';
  DELETE FROM users           WHERE id = 'a0000000-0000-0000-0000-000000000001';
"
echo "[Step 1] Done."

# ---- Step 2: Seed user (seller) ----
echo "[Step 2] Seeding seller user..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO users (id, email, password_hash, role, status, created_at)
  VALUES (
    'a0000000-0000-0000-0000-000000000001',
    'seller1@example.com',
    'hashed_pw',
    'SELLER',
    'ACTIVE',
    NOW()
  );
"
echo "[Step 2] Done."

# ---- Step 3: Seed seller profile ----
echo "[Step 3] Seeding seller profile..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO seller_profiles (id, user_id, store_name, bio)
  VALUES (
    'b0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000001',
    'Artisan Workshop',
    'Handcrafted goods from our studio'
  );
"
echo "[Step 3] Done."

# ---- Step 4: Seed active product ----
# Note: products.seller_id references seller_profiles.id, not users.id
echo "[Step 4] Seeding active product..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
  VALUES (
    'c0000000-0000-0000-0000-000000000001',
    'b0000000-0000-0000-0000-000000000001',
    'Handmade Ceramic Mug',
    'A beautifully crafted ceramic mug',
    'ceramics',
    2500,
    10,
    '[\"https://example.com/mug.jpg\"]',
    'ACTIVE',
    true,
    NOW()
  );
"
echo "[Step 4] Done."

# ---- Step 5: Call GET /products (no auth, no query params) ----
echo "[Step 5] Calling GET $APP_URL/products ..."
RESPONSE=$(curl -s -w "
%{http_code}" "$APP_URL/products")
HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)

echo "Status: $HTTP_STATUS"
echo "Body: $HTTP_BODY"

# ---- Step 6: Assert HTTP 200 ----
echo "[Step 6] Asserting HTTP 200..."
if [ "$HTTP_STATUS" != "200" ]; then
  echo "FAIL: Expected HTTP 200, got $HTTP_STATUS"
  exit 1
fi
echo "PASS: HTTP 200"

# ---- Step 7: Assert response is a non-empty JSON array ----
echo "[Step 7] Asserting non-empty JSON array..."
IS_ARRAY=$(echo "$HTTP_BODY" | jq 'type == "array"')
ARRAY_LEN=$(echo "$HTTP_BODY" | jq 'length')

if [ "$IS_ARRAY" != "true" ]; then
  echo "FAIL: Response is not a JSON array"
  exit 1
fi
if [ "$ARRAY_LEN" -lt 1 ]; then
  echo "FAIL: Expected at least 1 product, got $ARRAY_LEN"
  exit 1
fi
echo "PASS: JSON array with $ARRAY_LEN item(s)"

# ---- Step 8: Assert seeded product appears in the array ----
echo "[Step 8] Asserting seeded product is in response..."
PRODUCT=$(echo "$HTTP_BODY" | jq '.[] | select(.id == "c0000000-0000-0000-0000-000000000001")')
if [ -z "$PRODUCT" ]; then
  echo "FAIL: Seeded product not found in response"
  exit 1
fi
echo "PASS: Seeded product found"

# ---- Step 9: Assert required fields on the returned product ----
echo "[Step 9] Asserting required fields..."
check_field() {
  local FIELD=$1
  local VALUE
  VALUE=$(echo "$PRODUCT" | jq -r ".$FIELD")
  if [ "$VALUE" = "null" ] || [ -z "$VALUE" ]; then
    echo "FAIL: Field '$FIELD' is missing or null"
    exit 1
  fi
  echo "PASS: Field '$FIELD' = $VALUE"
}

check_field "id"
check_field "title"
check_field "description"

# price may be exposed as price_cents or price
PRICE=$(echo "$PRODUCT" | jq '.price_cents // .price')
if [ "$PRICE" = "null" ] || [ -z "$PRICE" ]; then
  echo "FAIL: Neither 'price_cents' nor 'price' field present"
  exit 1
fi
echo "PASS: Price field present = $PRICE"

# imageUrl may be exposed as photos, imageUrl, or image_url
IMAGE=$(echo "$PRODUCT" | jq -r '.imageUrl // .image_url // (.photos | if type == "array" then .[0] else . end) // null')
if [ "$IMAGE" = "null" ] || [ -z "$IMAGE" ]; then
  echo "FAIL: No image field (imageUrl / image_url / photos) present"
  exit 1
fi
echo "PASS: Image field present = $IMAGE"

# store_name from seller join
STORE=$(echo "$PRODUCT" | jq -r '.store_name // .seller.store_name // null')
if [ "$STORE" = "null" ] || [ -z "$STORE" ]; then
  echo "FAIL: store_name not present (checked .store_name and .seller.store_name)"
  exit 1
fi
echo "PASS: store_name = $STORE"

# ---- Step 10: Assert REMOVED/invisible products are excluded (negative guard) ----
echo "[Step 10] Asserting REMOVED products are excluded..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
  VALUES (
    'c0000000-0000-0000-0000-000000000099',
    'b0000000-0000-0000-0000-000000000001',
    'Removed Product',
    'Should not appear',
    'ceramics',
    100,
    0,
    '[]',
    'REMOVED',
    true,
    NOW()
  );
"

RESPONSE2=$(curl -s "$APP_URL/products")
REMOVED_ITEM=$(echo "$RESPONSE2" | jq '.[] | select(.id == "c0000000-0000-0000-0000-000000000099")')
if [ -n "$REMOVED_ITEM" ]; then
  echo "FAIL: REMOVED product appeared in catalog response"
  exit 1
fi
echo "PASS: REMOVED product correctly excluded"

# ---- Step 11: Cleanup ----
echo "[Step 11] Cleaning up test data..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  DELETE FROM products        WHERE id IN ('c0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000099');
  DELETE FROM seller_profiles WHERE id = 'b0000000-0000-0000-0000-000000000001';
  DELETE FROM users            WHERE id = 'a0000000-0000-0000-0000-000000000001';
"
echo "Cleanup complete"

echo "CODEVALID_TEST_ASSERTION_OK:catalog_listing_returns_active_products"
