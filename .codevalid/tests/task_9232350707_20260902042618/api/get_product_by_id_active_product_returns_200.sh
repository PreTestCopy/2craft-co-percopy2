#!/usr/bin/env bash
# Case: get_product_by_id_active_product_returns_200
# Verify GET /products/:id returns HTTP 200 with full product detail for an active, visible product.
set -euo pipefail

source .codevalid/tests/task_9232350707_20260902042618/api/_infra.sh

# ── Seed: create seller user ────────────────────────────────────────────
SELLER_USER_ID="user_$(date +%s%N)"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO users (id, email, password_hash, role, status)
  VALUES (
    '${SELLER_USER_ID}',
    'seller_${SELLER_USER_ID}@test.example',
    'hashed_irrelevant',
    'SELLER',
    'ACTIVE'
  );
"

# ── Seed: create seller profile ───────────────────────────────────────────
SELLER_PROFILE_ID="sp_$(date +%s%N)"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO seller_profiles (id, user_id, store_name, bio)
  VALUES (
    '${SELLER_PROFILE_ID}',
    '${SELLER_USER_ID}',
    'Test Artisan Store',
    'Great handmade goods'
  );
"

# ── Seed: create active visible product ───────────────────────────────────────────
PRODUCT_ID="prod_$(date +%s%N)"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible)
  VALUES (
    '${PRODUCT_ID}',
    '${SELLER_PROFILE_ID}',
    'Handmade Ceramic Bowl',
    'A beautiful hand-thrown ceramic bowl',
    'Ceramics',
    4999,
    10,
    '[]',
    'ACTIVE',
    true
  );
"

# ── Seed: create buyer user (for review) ─────────────────────────────────────────
BUYER_USER_ID="buyer_$(date +%s%N)"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO users (id, email, password_hash, role, status)
  VALUES (
    '${BUYER_USER_ID}',
    'buyer_${BUYER_USER_ID}@test.example',
    'hashed_irrelevant',
    'BUYER',
    'ACTIVE'
  );
"

# ── Seed: create order (required for order_item FK) ──────────────────────────────────
ORDER_ID="order_$(date +%s%N)"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO orders (id, buyer_id, status, total_cents, platform_fee_cents)
  VALUES (
    '${ORDER_ID}',
    '${BUYER_USER_ID}',
    'PAID',
    4999,
    500
  );
"

# ── Seed: create order item (required for review FK) ─────────────────────────────────
ORDER_ITEM_ID="oi_$(date +%s%N)"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO order_items (id, order_id, product_id, seller_id, qty, price_at_purchase, seller_payout_cents)
  VALUES (
    '${ORDER_ITEM_ID}',
    '${ORDER_ID}',
    '${PRODUCT_ID}',
    '${SELLER_PROFILE_ID}',
    1,
    4999,
    4499
  );
"

# ── Seed: create review ───────────────────────────────────────────────────────────────────────────────────────────────
REVIEW_ID="rev_$(date +%s%N)"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO reviews (id, order_item_id, product_id, buyer_id, rating, body)
  VALUES (
    '${REVIEW_ID}',
    '${ORDER_ITEM_ID}',
    '${PRODUCT_ID}',
    '${BUYER_USER_ID}',
    5,
    'Absolutely stunning piece!'
  );
"

# ── When: GET /products/:id with no auth ──────────────────────────────────────────────────────
RESPONSE=$(curl -s -w "
%{http_code}" \
  -H "Accept: application/json" \
  "${BASE_URL}/products/${PRODUCT_ID}")

HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)

echo "Status: $HTTP_STATUS"
echo "Body: $HTTP_BODY"

# ── Then: assert HTTP 200 ──────────────────────────────────────────────────────────────────────────────────────────────────────
if [ "$HTTP_STATUS" != "200" ]; then
  echo "FAIL: expected HTTP 200, got $HTTP_STATUS"
  exit 1
fi

# ── Then: assert top-level product fields ─────────────────────────────────────────────────────────────────────────
ACTUAL_ID=$(echo "$HTTP_BODY" | jq -r '.id')
ACTUAL_TITLE=$(echo "$HTTP_BODY" | jq -r '.title')
ACTUAL_DESCRIPTION=$(echo "$HTTP_BODY" | jq -r '.description')
ACTUAL_CATEGORY=$(echo "$HTTP_BODY" | jq -r '.category')
ACTUAL_PRICE=$(echo "$HTTP_BODY" | jq -r '.price_cents')
ACTUAL_STOCK=$(echo "$HTTP_BODY" | jq -r '.stock_qty')
ACTUAL_STATUS=$(echo "$HTTP_BODY" | jq -r '.status')
ACTUAL_VISIBLE=$(echo "$HTTP_BODY" | jq -r '.visible')
ACTUAL_STORE=$(echo "$HTTP_BODY" | jq -r '.store_name')
REVIEWS_LEN=$(echo "$HTTP_BODY" | jq '.reviews | length')

[ "$ACTUAL_ID" = "$PRODUCT_ID" ]           || { echo "FAIL: id mismatch: $ACTUAL_ID"; exit 1; }
[ "$ACTUAL_TITLE" = "Handmade Ceramic Bowl" ] || { echo "FAIL: title mismatch: $ACTUAL_TITLE"; exit 1; }
[ "$ACTUAL_DESCRIPTION" = "A beautiful hand-thrown ceramic bowl" ] || { echo "FAIL: description mismatch"; exit 1; }
[ "$ACTUAL_CATEGORY" = "Ceramics" ]        || { echo "FAIL: category mismatch: $ACTUAL_CATEGORY"; exit 1; }
[ "$ACTUAL_PRICE" = "4999" ]               || { echo "FAIL: price_cents mismatch: $ACTUAL_PRICE"; exit 1; }
[ "$ACTUAL_STOCK" = "10" ]                 || { echo "FAIL: stock_qty mismatch: $ACTUAL_STOCK"; exit 1; }
[ "$ACTUAL_STATUS" = "active" ]            || { echo "FAIL: derived status should be 'active', got: $ACTUAL_STATUS"; exit 1; }
[ "$ACTUAL_VISIBLE" = "true" ]             || { echo "FAIL: visible should be true, got: $ACTUAL_VISIBLE"; exit 1; }
[ "$ACTUAL_STORE" = "Test Artisan Store" ] || { echo "FAIL: store_name mismatch: $ACTUAL_STORE"; exit 1; }
[ "$REVIEWS_LEN" = "1" ]                   || { echo "FAIL: expected 1 review, got: $REVIEWS_LEN"; exit 1; }

# ── Then: assert review fields ──────────────────────────────────────────────────────────────────────────────────────────────────
REVIEW_RATING=$(echo "$HTTP_BODY" | jq -r '.reviews[0].rating')
REVIEW_BODY=$(echo "$HTTP_BODY" | jq -r '.reviews[0].body')
REVIEW_BUYER_EMAIL=$(echo "$HTTP_BODY" | jq -r '.reviews[0].buyer_email')

[ "$REVIEW_RATING" = "5" ]                 || { echo "FAIL: review rating mismatch: $REVIEW_RATING"; exit 1; }
[ "$REVIEW_BODY" = "Absolutely stunning piece!" ] || { echo "FAIL: review body mismatch: $REVIEW_BODY"; exit 1; }
# buyer_email must be masked (contains ***)
echo "$REVIEW_BUYER_EMAIL" | grep -q '\*\*\*' || { echo "FAIL: buyer_email not masked: $REVIEW_BUYER_EMAIL"; exit 1; }

echo "PASS: get_product_by_id_active_product_returns_200"
echo "CODEVALID_TEST_ASSERTION_OK:get_product_by_id_active_product_returns_200"
