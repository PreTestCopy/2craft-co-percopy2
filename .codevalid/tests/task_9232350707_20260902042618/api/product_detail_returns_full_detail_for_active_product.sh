#!/usr/bin/env bash
# Case: product_detail_returns_full_detail_for_active_product
# Verifies GET /products/:id returns HTTP 200 with complete product detail for an active product.
set -euo pipefail

# 1. Source shared infra
source .codevalid/tests/task_9232350707_20260902042618/api/_infra.sh

# 2. Seed values
SELLER_EMAIL="seller_detail_test@example.com"
SELLER_PASSWORD_HASH='$2b$10$placeholder_bcrypt_hash'
STORE_NAME="Artisan Corner"
PRODUCT_TITLE="Handcrafted Ceramic Mug"
PRODUCT_DESCRIPTION="A beautiful hand-thrown ceramic mug glazed in ocean blue."
PRODUCT_CATEGORY="ceramics"
PRODUCT_PRICE_CENTS=2500
PRODUCT_STOCK_QTY=10
PRODUCT_PHOTOS='["https://cdn.example.com/mug.jpg"]'

# 5. Run seed
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f mappings/cases/product_detail_returns_full_detail_for_active_product/seed.sql

# 6. Capture seeded product id
PRODUCT_ID=$(psql "$DATABASE_URL" -t -A -c \
  "SELECT id FROM products WHERE title = 'Handcrafted Ceramic Mug' AND status = 'ACTIVE' LIMIT 1;")
echo "PRODUCT_ID=${PRODUCT_ID}"

# 7. When — HTTP request
RESPONSE=$(curl -s -w "
%{http_code}" \
  -H "Accept: application/json" \
  "${APP_URL}/products/${PRODUCT_ID}")

HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)

# 8. Then — assertions

# Assert HTTP 200
[ "$HTTP_STATUS" -eq 200 ] \
  || { echo "FAIL: expected 200, got $HTTP_STATUS"; exit 1; }

# Assert id matches seeded product
RESP_ID=$(echo "$HTTP_BODY" | jq -r '.id')
[ "$RESP_ID" = "$PRODUCT_ID" ] \
  || { echo "FAIL: id mismatch: expected $PRODUCT_ID, got $RESP_ID"; exit 1; }

# Assert required fields are present and non-null/non-empty
for FIELD in title description category price_cents stock_qty photos status visible; do
  VAL=$(echo "$HTTP_BODY" | jq -r --arg f "$FIELD" '.[$f]')
  [ "$VAL" != "null" ] && [ -n "$VAL" ] \
    || { echo "FAIL: field '$FIELD' is null or missing"; exit 1; }
done

# Assert store_name (seller join)
STORE=$(echo "$HTTP_BODY" | jq -r '.store_name // .seller.store_name // .seller.storeName // empty')
[ "$STORE" = "Artisan Corner" ] \
  || { echo "FAIL: store_name mismatch: expected 'Artisan Corner', got '$STORE'"; exit 1; }

# Assert title value
RESP_TITLE=$(echo "$HTTP_BODY" | jq -r '.title')
[ "$RESP_TITLE" = "Handcrafted Ceramic Mug" ] \
  || { echo "FAIL: title mismatch: got '$RESP_TITLE'"; exit 1; }

# Assert price_cents value
RESP_PRICE=$(echo "$HTTP_BODY" | jq -r '.price_cents')
[ "$RESP_PRICE" = "2500" ] \
  || { echo "FAIL: price_cents mismatch: got '$RESP_PRICE'"; exit 1; }

# Assert no error fields
ERROR_FIELD=$(echo "$HTTP_BODY" | jq -r '.error // empty')
[ -z "$ERROR_FIELD" ] \
  || { echo "FAIL: unexpected error field in response: $ERROR_FIELD"; exit 1; }

echo "PASS: product_detail_returns_full_detail_for_active_product"

# 9. Cleanup (optional isolation)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c \
  "DELETE FROM products WHERE title = 'Handcrafted Ceramic Mug';
   DELETE FROM seller_profiles WHERE store_name = 'Artisan Corner';
   DELETE FROM users WHERE email = 'seller_detail_test@example.com';"

echo "CODEVALID_TEST_ASSERTION_OK:product_detail_returns_full_detail_for_active_product"
