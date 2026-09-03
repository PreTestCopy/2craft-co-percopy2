#!/usr/bin/env bash
set -euo pipefail

source tests/task_9232350707_20260902042618/api/_infra.sh

# ── Case: product_detail_returns_full_detail_for_active_product ──

# 1. Seed: insert a seller user (use ON CONFLICT to handle re-runs)
SELLER_ID=$(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -tAc "
  INSERT INTO users (email, password_hash, role, status)
  VALUES (
    'seller_detail_test_9232@example.com',
    'hashed_pw',
    'ARTISAN',
    'ACTIVE'
  )
  ON CONFLICT (email) DO UPDATE SET email = EXCLUDED.email
  RETURNING id;
")

SELLER_ID=$(echo "$SELLER_ID" | tr -d '[:space:]')
echo "Seeded seller user id: $SELLER_ID"

# 2. Seed: insert seller_profile linked to that user (ON CONFLICT to handle re-runs)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO seller_profiles (user_id, store_name, bio)
  VALUES (
    '$SELLER_ID',
    'Detail Test Store',
    'A test artisan store'
  )
  ON CONFLICT (user_id) DO UPDATE SET store_name = EXCLUDED.store_name;
"

# 3. Seed: insert an active, visible product
PRODUCT_ID=$(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -tAc "
  INSERT INTO products (seller_id, title, description, category, price_cents, stock_qty, photos, status, visible)
  VALUES (
    '$SELLER_ID',
    'Handcrafted Mug',
    'A beautiful hand-thrown ceramic mug.',
    'CERAMICS',
    2500,
    10,
    ARRAY['https://example.com/mug.jpg'],
    'ACTIVE',
    true
  )
  RETURNING id;
")

PRODUCT_ID=$(echo "$PRODUCT_ID" | tr -d '[:space:]')
echo "Seeded product id: $PRODUCT_ID"

# 4. When: request the product detail by id (no Authorization header)
RESPONSE=$(curl -s -w "\n%{http_code}" "$APP_URL/products/$PRODUCT_ID")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)

echo "HTTP status: $STATUS"
echo "Response body: $BODY"

# 5. Then: assert HTTP 200
if [ "$STATUS" != "200" ]; then
  echo "FAIL: expected HTTP 200, got $STATUS"
  exit 1
fi

# 6. Then: assert id in response matches requested id
RESP_ID=$(echo "$BODY" | jq -r '.id // empty')
if [ "$RESP_ID" != "$PRODUCT_ID" ]; then
  echo "FAIL: response id '$RESP_ID' does not match seeded product id '$PRODUCT_ID'"
  exit 1
fi

# 7. Then: assert title matches seeded value
RESP_TITLE=$(echo "$BODY" | jq -r '.title // empty')
if [ "$RESP_TITLE" != "Handcrafted Mug" ]; then
  echo "FAIL: expected title 'Handcrafted Mug', got '$RESP_TITLE'"
  exit 1
fi

# 8. Then: assert store_name (or storeName) matches seeded value
RESP_STORE=$(echo "$BODY" | jq -r '.store_name // .storeName // empty')
if [ "$RESP_STORE" != "Detail Test Store" ]; then
  echo "FAIL: expected store_name 'Detail Test Store', got '$RESP_STORE'"
  exit 1
fi

# 9. Then: assert price field is present (price_cents or priceCents = 2500)
RESP_PRICE=$(echo "$BODY" | jq -r '.price_cents // .priceCents // empty')
if [ "$RESP_PRICE" != "2500" ]; then
  echo "FAIL: expected price_cents 2500, got '$RESP_PRICE'"
  exit 1
fi

echo "PASS: product_detail_returns_full_detail_for_active_product"
echo "CODEVALID_TEST_ASSERTION_OK:product_detail_returns_full_detail_for_active_product"