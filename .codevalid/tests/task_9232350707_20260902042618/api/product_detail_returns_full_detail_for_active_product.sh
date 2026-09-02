#!/usr/bin/env bash
# Case: product_detail_returns_full_detail_for_active_product
# Verifies GET /products/:id returns HTTP 200 with full product detail for an active product.
set -euo pipefail

# Source shared infra
source .codevalid/tests/task_9232350707_20260902042618/api/_infra.sh

# ---------------------------------------------------------------------------
# Seed values
# ---------------------------------------------------------------------------

# Insert a seller user
SELLER_ID=$(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -tAc "
  INSERT INTO users (email, password_hash, role, status, created_at)
  VALUES ('seller_detail@example.com', 'hashed_pw', 'USER', 'ACTIVE', NOW())
  RETURNING id;
")

# Insert a seller profile
SELLER_PROFILE_ID=$(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -tAc "
  INSERT INTO seller_profiles (user_id, store_name, bio)
  VALUES ('$SELLER_ID', 'Detail Test Store', 'A test artisan store')
  RETURNING id;
")

# Insert an active, visible product
PRODUCT_ID=$(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -tAc "
  INSERT INTO products (seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
  VALUES (
    '$SELLER_PROFILE_ID',
    'Handmade Ceramic Mug',
    'A beautiful handmade ceramic mug.',
    'ceramics',
    2500,
    10,
    ARRAY['https://example.com/mug.jpg'],
    'ACTIVE',
    true,
    NOW()
  )
  RETURNING id;
")

echo "Seeded PRODUCT_ID=$PRODUCT_ID"

# ---------------------------------------------------------------------------
# When
# ---------------------------------------------------------------------------
RESPONSE=$(curl -s -w "
%{http_code}" "$APP_URL/products/$PRODUCT_ID")
HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)

# ---------------------------------------------------------------------------
# Then
# ---------------------------------------------------------------------------

# Assert HTTP 200
[ "$HTTP_STATUS" -eq 200 ] || { echo "FAIL: expected 200, got $HTTP_STATUS"; exit 1; }

# Assert id matches
RESP_ID=$(echo "$HTTP_BODY" | jq -r '.id')
[ "$RESP_ID" = "$PRODUCT_ID" ] || { echo "FAIL: id mismatch. Expected $PRODUCT_ID got $RESP_ID"; exit 1; }

# Assert title
RESP_TITLE=$(echo "$HTTP_BODY" | jq -r '.title')
[ "$RESP_TITLE" = "Handmade Ceramic Mug" ] || { echo "FAIL: title mismatch, got $RESP_TITLE"; exit 1; }

# Assert description
RESP_DESC=$(echo "$HTTP_BODY" | jq -r '.description')
[ "$RESP_DESC" = "A beautiful handmade ceramic mug." ] || { echo "FAIL: description mismatch"; exit 1; }

# Assert category
RESP_CAT=$(echo "$HTTP_BODY" | jq -r '.category')
[ "$RESP_CAT" = "ceramics" ] || { echo "FAIL: category mismatch, got $RESP_CAT"; exit 1; }

# Assert price field present (price_cents or equivalent non-null)
RESP_PRICE=$(echo "$HTTP_BODY" | jq -r '.price_cents // .price // empty')
[ -n "$RESP_PRICE" ] || { echo "FAIL: price field missing or null"; exit 1; }

# Assert stock_qty present
RESP_STOCK=$(echo "$HTTP_BODY" | jq '.stock_qty // .stockQty // empty')
[ -n "$RESP_STOCK" ] || { echo "FAIL: stock_qty field missing"; exit 1; }

# Assert photos is an array with at least one entry
RESP_PHOTOS_LEN=$(echo "$HTTP_BODY" | jq '.photos | length')
[ "$RESP_PHOTOS_LEN" -ge 1 ] || { echo "FAIL: photos array empty or missing"; exit 1; }

# Assert seller store_name present
RESP_STORE=$(echo "$HTTP_BODY" | jq -r '.store_name // .seller.store_name // empty')
[ "$RESP_STORE" = "Detail Test Store" ] || { echo "FAIL: store_name mismatch, got $RESP_STORE"; exit 1; }

echo "PASS: product_detail_returns_full_detail_for_active_product"

# ---------------------------------------------------------------------------
# Teardown
# ---------------------------------------------------------------------------
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id = '$PRODUCT_ID';"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = '$SELLER_PROFILE_ID';"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '$SELLER_ID';"

echo "CODEVALID_TEST_ASSERTION_OK:product_detail_returns_full_detail_for_active_product"
