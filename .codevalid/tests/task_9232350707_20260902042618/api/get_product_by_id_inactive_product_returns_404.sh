#!/usr/bin/env bash
# Case: get_product_by_id_inactive_product_returns_404
# Verify that GET /products/:id returns HTTP 404 with {"error":"Product not found"}
# when the requested product exists but has visible=false (inactive/hidden from unauthenticated buyers).
set -euo pipefail

# Step 0 — Source shared infra
source .codevalid/tests/task_9232350707_20260902042618/api/_infra.sh

# Step 1a — insert a seller user (required FK for seller_profiles)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, created_at)
VALUES (
  'seed-user-seller-inactive-01',
  'seller-inactive@example.com',
  'hashed_placeholder',
  'SELLER',
  NOW()
) ON CONFLICT (id) DO NOTHING;
"

# Step 1b — insert a seller profile (required FK for products.seller_id)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES (
  'seed-seller-profile-inactive-01',
  'seed-user-seller-inactive-01',
  'Inactive Test Store',
  'Test seller for inactive product scenario'
) ON CONFLICT (id) DO NOTHING;
"

# Step 1c — insert an invisible product (visible=false, status='ACTIVE', NOT 'REMOVED')
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES (
  'seed-product-inactive-01',
  'seed-seller-profile-inactive-01',
  'Hidden Artisan Bowl',
  'A beautiful hand-crafted bowl that is currently hidden from buyers.',
  'CERAMICS',
  4999,
  10,
  '[]',
  'ACTIVE',
  false,
  NOW()
) ON CONFLICT (id) DO NOTHING;
"

# Step 2 — When: send the request (no auth token — unauthenticated buyer)
PRODUCT_ID="seed-product-inactive-01"

RESPONSE=$(curl -s -w "
%{http_code}" \
  -H "Accept: application/json" \
  "${BASE_URL}/products/${PRODUCT_ID}")

HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)

# Step 3 — Then: assert HTTP 404
if [ "$HTTP_STATUS" != "404" ]; then
  echo "FAIL: Expected HTTP 404, got $HTTP_STATUS"
  echo "Response body: $HTTP_BODY"
  # Teardown before exit
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  DELETE FROM products WHERE id = 'seed-product-inactive-01';
  DELETE FROM seller_profiles WHERE id = 'seed-seller-profile-inactive-01';
  DELETE FROM users WHERE id = 'seed-user-seller-inactive-01';
  " || true
  exit 1
fi
echo "PASS: HTTP status is 404"

# Step 4 — Then: assert error payload
ERROR_MSG=$(echo "$HTTP_BODY" | jq -r '.error // empty')

if [ "$ERROR_MSG" != "Product not found" ]; then
  echo "FAIL: Expected error 'Product not found', got '$ERROR_MSG'"
  echo "Full response: $HTTP_BODY"
  # Teardown before exit
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  DELETE FROM products WHERE id = 'seed-product-inactive-01';
  DELETE FROM seller_profiles WHERE id = 'seed-seller-profile-inactive-01';
  DELETE FROM users WHERE id = 'seed-user-seller-inactive-01';
  " || true
  exit 1
fi
echo "PASS: Error message is 'Product not found'"

# Step 5 — Then: assert no product data leaked
TITLE=$(echo "$HTTP_BODY" | jq -r '.title // empty')
ID_FIELD=$(echo "$HTTP_BODY" | jq -r '.id // empty')

if [ -n "$TITLE" ] || [ -n "$ID_FIELD" ]; then
  echo "FAIL: Response leaked product data (title='$TITLE', id='$ID_FIELD')"
  # Teardown before exit
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  DELETE FROM products WHERE id = 'seed-product-inactive-01';
  DELETE FROM seller_profiles WHERE id = 'seed-seller-profile-inactive-01';
  DELETE FROM users WHERE id = 'seed-user-seller-inactive-01';
  " || true
  exit 1
fi
echo "PASS: No product data leaked in 404 response"

# Step 6 — Teardown: remove seed rows
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
DELETE FROM products WHERE id = 'seed-product-inactive-01';
DELETE FROM seller_profiles WHERE id = 'seed-seller-profile-inactive-01';
DELETE FROM users WHERE id = 'seed-user-seller-inactive-01';
"
echo "Teardown complete"

echo "CODEVALID_TEST_ASSERTION_OK:get_product_by_id_inactive_product_returns_404"
