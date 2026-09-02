#!/usr/bin/env bash
# Case: get_product_by_id_active_product_returns_200
# Verify that GET /products/:id returns HTTP 200 with full product detail for an active, visible product.
set -euo pipefail

# Setup
source .codevalid/tests/task_9232350707_20260902042618/api/_infra.sh

# Seed Values
SELLER_USER_ID="seller-user-1"
SELLER_USER_EMAIL="seller@example.com"
SELLER_PROFILE_ID="seller-profile-1"
SELLER_STORE_NAME="Test Artisan Shop"
PRODUCT_ID="product-active-1"
PRODUCT_TITLE="Handmade Vase"
PRODUCT_DESCRIPTION="A beautiful vase"
PRODUCT_CATEGORY="Home Decor"
PRODUCT_PRICE_CENTS=4999
PRODUCT_STOCK_QTY=10
PRODUCT_STATUS="ACTIVE"
PRODUCT_VISIBLE=true

# Seed SQL
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO users (id, email)
  VALUES ('seller-user-1', 'seller@example.com')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO seller_profiles (id, user_id, store_name, bio)
  VALUES ('seller-profile-1', 'seller-user-1', 'Test Artisan Shop', 'Bio text')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
  VALUES (
    'product-active-1',
    'seller-profile-1',
    'Handmade Vase',
    'A beautiful vase',
    'Home Decor',
    4999,
    10,
    '[]',
    'ACTIVE',
    true,
    NOW()
  )
  ON CONFLICT (id) DO NOTHING;
"

# When
RESPONSE=$(curl -s -w "
%{http_code}" \
  -H "Accept: application/json" \
  "${BASE_URL}/products/product-active-1")

HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)

# Then

# 1. Assert HTTP 200
[ "$HTTP_STATUS" = "200" ] || {
  echo "FAIL: expected HTTP 200, got $HTTP_STATUS"
  echo "Body: $HTTP_BODY"
  exit 1
}

# 2. Assert no top-level error field
echo "$HTTP_BODY" | jq -e 'has("error") | not' || {
  echo "FAIL: response contains unexpected error field"
  echo "Body: $HTTP_BODY"
  exit 1
}

# 3. Assert id
ACTUAL_ID=$(echo "$HTTP_BODY" | jq -r '.id')
[ "$ACTUAL_ID" = "product-active-1" ] || {
  echo "FAIL: expected id='product-active-1', got '$ACTUAL_ID'"
  exit 1
}

# 4. Assert title
ACTUAL_TITLE=$(echo "$HTTP_BODY" | jq -r '.title')
[ "$ACTUAL_TITLE" = "Handmade Vase" ] || {
  echo "FAIL: expected title='Handmade Vase', got '$ACTUAL_TITLE'"
  exit 1
}

# 5. Assert description
ACTUAL_DESC=$(echo "$HTTP_BODY" | jq -r '.description')
[ "$ACTUAL_DESC" = "A beautiful vase" ] || {
  echo "FAIL: expected description='A beautiful vase', got '$ACTUAL_DESC'"
  exit 1
}

# 6. Assert price_cents (or mapped price field)
ACTUAL_PRICE=$(echo "$HTTP_BODY" | jq -r '.price_cents // .price')
[ "$ACTUAL_PRICE" = "4999" ] || {
  echo "FAIL: expected price_cents=4999, got '$ACTUAL_PRICE'"
  exit 1
}

# 7. Assert store_name present and correct
ACTUAL_STORE=$(echo "$HTTP_BODY" | jq -r '.store_name // .seller.store_name')
[ "$ACTUAL_STORE" = "Test Artisan Shop" ] || {
  echo "FAIL: expected store_name='Test Artisan Shop', got '$ACTUAL_STORE'"
  exit 1
}

# 8. Assert reviews is an array
echo "$HTTP_BODY" | jq -e '.reviews | type == "array"' || {
  echo "FAIL: expected reviews to be an array"
  echo "Body: $HTTP_BODY"
  exit 1
}

echo "PASS: get_product_by_id_active_product_returns_200"

# Teardown
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  DELETE FROM products WHERE id = 'product-active-1';
  DELETE FROM seller_profiles WHERE id = 'seller-profile-1';
  DELETE FROM users WHERE id = 'seller-user-1';
"

echo "CODEVALID_TEST_ASSERTION_OK:get_product_by_id_active_product_returns_200"
