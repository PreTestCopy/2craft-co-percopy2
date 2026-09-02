#!/usr/bin/env bash
# Case: product_detail_404_for_inactive_product
# Verify that GET /products/:id returns HTTP 404 with a clear error payload
# when the requested product is inactive (visible=false, status='INACTIVE').
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_infra.sh
source "${SCRIPT_DIR}/_infra.sh"

# ---------------------------------------------------------------------------
# Seed values
# ---------------------------------------------------------------------------
SELLER_USER_ID='usr-inactive-prod-01'
SELLER_PROFILE_ID='sp-inactive-prod-01'
PRODUCT_ID='prod-inactive-01'

# ---------------------------------------------------------------------------
# Seed: insert seller user, seller profile, and inactive product
# ---------------------------------------------------------------------------
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('usr-inactive-prod-01','seller_inactive@example.com','hash_placeholder','SELLER','ACTIVE',NOW())
ON CONFLICT (id) DO NOTHING;

INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('sp-inactive-prod-01','usr-inactive-prod-01','Inactive Goods Store','Test store for inactive product case')
ON CONFLICT (id) DO NOTHING;

INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES ('prod-inactive-01','usr-inactive-prod-01','Invisible Vase','A product that is not visible to buyers','HOME_DECOR',2500,10,'[]','INACTIVE',false,NOW())
ON CONFLICT (id) DO NOTHING;
"

# ---------------------------------------------------------------------------
# When: GET /products/:id for an inactive product
# ---------------------------------------------------------------------------
RESPONSE=$(curl -s -w "
%{http_code}" \
  "${APP_URL}/products/${PRODUCT_ID}")

HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)

# ---------------------------------------------------------------------------
# Then: assertions
# ---------------------------------------------------------------------------

# Assert HTTP 404
if [ "$HTTP_STATUS" != "404" ]; then
  echo "FAIL: Expected HTTP 404 for inactive product, got $HTTP_STATUS"
  echo "Body: $HTTP_BODY"
  exit 1
fi

# Assert response body is valid JSON
echo "$HTTP_BODY" | jq . > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "FAIL: Response body is not valid JSON"
  echo "Body: $HTTP_BODY"
  exit 1
fi

# Assert error payload contains an error field
ERROR_FIELD=$(echo "$HTTP_BODY" | jq -r '.error // .message // empty')
if [ -z "$ERROR_FIELD" ]; then
  echo "FAIL: Response JSON does not contain an 'error' or 'message' field"
  echo "Body: $HTTP_BODY"
  exit 1
fi

# Assert the product detail fields are NOT exposed
PRODUCT_TITLE=$(echo "$HTTP_BODY" | jq -r '.title // empty')
if [ -n "$PRODUCT_TITLE" ]; then
  echo "FAIL: Response unexpectedly contains product title: $PRODUCT_TITLE"
  exit 1
fi

echo "PASS: GET /products/$PRODUCT_ID returned 404 with error payload for inactive product"
echo "Error message: $ERROR_FIELD"

# ---------------------------------------------------------------------------
# Teardown (optional)
# ---------------------------------------------------------------------------
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
DELETE FROM products WHERE id = 'prod-inactive-01';
DELETE FROM seller_profiles WHERE id = 'sp-inactive-prod-01';
DELETE FROM users WHERE id = 'usr-inactive-prod-01';
" || true

echo "CODEVALID_TEST_ASSERTION_OK:product_detail_404_for_inactive_product"
