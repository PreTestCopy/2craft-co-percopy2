#!/usr/bin/env bash
set -euo pipefail

source tests/task_9232350707_20260902042618/api/_infra.sh

# ── Helper ────────────────────────────────────────────────────────────────────
extract_uuid() {
  echo "$1" | grep -Eo '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -n 1
}

# ── Seed ──────────────────────────────────────────────────────────────────────

# 1. Parent: users row (role=SELLER is the schema-valid artisan role; ARTISAN does not exist)
RAW_USER=$(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -tAc "
  INSERT INTO users (id, email, password_hash, role, status, created_at)
  VALUES (gen_random_uuid(), 'artisan_detail@example.com', 'hash_placeholder', 'SELLER', 'ACTIVE', now())
  ON CONFLICT (email) DO UPDATE SET status = EXCLUDED.status
  RETURNING id;
")
USER_ID=$(extract_uuid "$RAW_USER")
echo "Seeded user id: $USER_ID"
[ -n "$USER_ID" ] || { echo "FAIL: could not extract user UUID"; exit 1; }

# 2. Parent: seller_profiles row linked to the user
RAW_PROFILE=$(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -tAc "
  INSERT INTO seller_profiles (id, user_id, store_name, bio)
  VALUES (gen_random_uuid(), '$USER_ID', 'Detail Test Store', 'A bio for the detail test store')
  ON CONFLICT (user_id) DO UPDATE SET store_name = EXCLUDED.store_name
  RETURNING id;
")
SELLER_ID=$(extract_uuid "$RAW_PROFILE")
echo "Seeded seller_profile id: $SELLER_ID"
[ -n "$SELLER_ID" ] || { echo "FAIL: could not extract seller_profile UUID"; exit 1; }

# 3. Child: products row with status ACTIVE and visible true
#    photos is Json in the schema; seed as empty JSON array cast to jsonb
RAW_PRODUCT=$(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -tAc "
  INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
  VALUES (
    gen_random_uuid(),
    '$SELLER_ID',
    'Handcrafted Ceramic Mug',
    'A beautifully handcrafted ceramic mug.',
    'CERAMICS',
    2500,
    10,
    '[]'::jsonb,
    'ACTIVE',
    true,
    now()
  )
  RETURNING id;
")
PRODUCT_ID=$(extract_uuid "$RAW_PRODUCT")
echo "Seeded product id: $PRODUCT_ID"
[ -n "$PRODUCT_ID" ] || { echo "FAIL: could not extract product UUID"; exit 1; }

# ── Case: product_detail_returns_full_detail_for_active_product ───────────────

# When: GET /products/:id with a valid active product id
RESPONSE=$(curl -s -w "
%{http_code}" "$APP_URL/products/$PRODUCT_ID")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)

echo "HTTP status: $STATUS"
echo "Response body: $BODY"

# Then: HTTP 200
[ "$STATUS" = "200" ] || { echo "FAIL: expected 200, got $STATUS"; exit 1; }

# Then: response body contains the product id
echo "$BODY" | jq -e --arg id "$PRODUCT_ID" '.id == $id' \
  || { echo "FAIL: id mismatch. Body: $BODY"; exit 1; }

# Then: title matches seeded value
echo "$BODY" | jq -e '.title == "Handcrafted Ceramic Mug"' \
  || { echo "FAIL: title mismatch. Body: $BODY"; exit 1; }

# Then: description matches seeded value
echo "$BODY" | jq -e '.description == "A beautifully handcrafted ceramic mug."' \
  || { echo "FAIL: description mismatch. Body: $BODY"; exit 1; }

# Then: price field present (price_cents or priceCents)
echo "$BODY" | jq -e '(.price_cents // .priceCents) == 2500' \
  || { echo "FAIL: price_cents mismatch. Body: $BODY"; exit 1; }

# Then: seller store_name present (flat or nested)
echo "$BODY" | jq -e '(.store_name // .storeName // .seller.store_name // .seller.storeName) == "Detail Test Store"' \
  || { echo "FAIL: store_name missing or wrong. Body: $BODY"; exit 1; }

# Then: status is ACTIVE
echo "$BODY" | jq -e '.status == "ACTIVE"' \
  || { echo "FAIL: status mismatch. Body: $BODY"; exit 1; }

# Then: category is present
echo "$BODY" | jq -e '.category == "CERAMICS"' \
  || { echo "FAIL: category mismatch. Body: $BODY"; exit 1; }

echo "PASS: product_detail_returns_full_detail_for_active_product"
echo "CODEVALID_TEST_ASSERTION_OK:product_detail_returns_full_detail_for_active_product"
