#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root so this script can be run from any working directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
cd "${REPO_ROOT}"

source .codevalid/tests/task_9232350707_20260902042618/api/_infra.sh

CASE_DIR="mappings/cases/catalog_listing_excludes_inactive_products"

# ── Seed ──────────────────────────────────────────────────────────────────────
echo "[seed] Inserting test data..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "${CASE_DIR}/seed.sql"
echo "[seed] Done."

# ── When: unauthenticated GET /products ──────────────────────────────────────
echo "[test] Calling GET /products (no auth)..."
RESPONSE=$(curl -s -w "
%{http_code}" "${APP_URL}/products")
HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)

echo "[test] HTTP status: ${HTTP_STATUS}"
echo "[test] Response body: ${HTTP_BODY}"

# ── Then: HTTP 200 ────────────────────────────────────────────────────────────
if [ "$HTTP_STATUS" != "200" ]; then
  echo "[FAIL] Expected HTTP 200, got ${HTTP_STATUS}"
  exit 1
fi
echo "[PASS] HTTP status is 200"

# ── Then: response is a JSON array ───────────────────────────────────────────
ARRAY_LENGTH=$(echo "$HTTP_BODY" | jq 'length')
echo "[test] Array length: ${ARRAY_LENGTH}"

# ── Then: active+visible product IS present ───────────────────────────────────
ACTIVE_COUNT=$(echo "$HTTP_BODY" | jq '[.[] | select(.id == "prod-active-001")] | length')
if [ "$ACTIVE_COUNT" -ne 1 ]; then
  echo "[FAIL] Expected prod-active-001 to appear exactly once, got ${ACTIVE_COUNT}"
  exit 1
fi
echo "[PASS] Active+visible product prod-active-001 is present in catalog"

# ── Then: REMOVED product is NOT present ─────────────────────────────────────
REMOVED_COUNT=$(echo "$HTTP_BODY" | jq '[.[] | select(.id == "prod-removed-002")] | length')
if [ "$REMOVED_COUNT" -ne 0 ]; then
  echo "[FAIL] REMOVED product prod-removed-002 must not appear in catalog, found ${REMOVED_COUNT} occurrence(s)"
  exit 1
fi
echo "[PASS] REMOVED product prod-removed-002 is excluded from catalog"

# ── Then: hidden (visible=false) product is NOT present ──────────────────────
HIDDEN_COUNT=$(echo "$HTTP_BODY" | jq '[.[] | select(.id == "prod-hidden-003")] | length')
if [ "$HIDDEN_COUNT" -ne 0 ]; then
  echo "[FAIL] Hidden product prod-hidden-003 (visible=false) must not appear for unauthenticated caller, found ${HIDDEN_COUNT} occurrence(s)"
  exit 1
fi
echo "[PASS] Hidden product prod-hidden-003 is excluded from catalog for unauthenticated caller"

# ── Then: active product has required fields ──────────────────────────────────
ACTIVE_PRODUCT=$(echo "$HTTP_BODY" | jq '.[] | select(.id == "prod-active-001")')

for FIELD in id title description price_cents; do
  VALUE=$(echo "$ACTIVE_PRODUCT" | jq -r --arg f "$FIELD" '.[$f] // empty')
  if [ -z "$VALUE" ]; then
    echo "[FAIL] Required field '${FIELD}' is missing or null in catalog product"
    exit 1
  fi
  echo "[PASS] Field '${FIELD}' present: ${VALUE}"
done

# store_name may be nested under seller or as a top-level field depending on formatProduct
STORE_NAME=$(echo "$ACTIVE_PRODUCT" | jq -r '.store_name // .seller.store_name // empty')
if [ -z "$STORE_NAME" ]; then
  echo "[FAIL] seller store_name is missing from catalog product"
  exit 1
fi
echo "[PASS] store_name present: ${STORE_NAME}"

echo ""
echo "=== ALL ASSERTIONS PASSED for catalog_listing_excludes_inactive_products ==="
echo "CODEVALID_TEST_ASSERTION_OK:catalog_listing_excludes_inactive_products"
