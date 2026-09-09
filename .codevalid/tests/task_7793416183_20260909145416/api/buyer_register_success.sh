#!/usr/bin/env bash
set -euo pipefail

# Setup
source tests/task_7793416183_20260909145416/api/_infra.sh

APP_PORT="6713"
export APP_PORT

wait_for_tcp "toxiproxy:5432"
wait_for_http "http://app:${APP_PORT}/health"

# Case: buyer_register_success

## Preconditions
BUYER_EMAIL="buyer_success_$(date +%s)@example.com"
BUYER_PASSWORD="StrongPass$(date +%s)"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE email = '${BUYER_EMAIL}';"

## When
curl -sS -X POST "http://app:${APP_PORT}/auth/register" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg email "$BUYER_EMAIL" --arg password "$BUYER_PASSWORD" --arg role "BUYER" '{email: $email, password: $password, role: $role}')" \
  -o /tmp/buyer_register_success.json \
  -w "%{http_code}" > /tmp/buyer_register_success_status.txt

## Then
STATUS_CODE="$(cat /tmp/buyer_register_success_status.txt)"
test "$STATUS_CODE" -eq 201

jq -e '.token' /tmp/buyer_register_success.json > /dev/null
jq -e '.user' /tmp/buyer_register_success.json > /dev/null
jq -e '.user.id' /tmp/buyer_register_success.json > /dev/null
jq -e '.user.email' /tmp/buyer_register_success.json > /dev/null
jq -e '.user.role' /tmp/buyer_register_success.json > /dev/null
jq -e '.user.status' /tmp/buyer_register_success.json > /dev/null

test "$(jq -r '.user.role' /tmp/buyer_register_success.json)" = "BUYER"
test "$(jq -r '.user.status' /tmp/buyer_register_success.json)" = "ACTIVE"
test "$(jq -r '.user.email' /tmp/buyer_register_success.json)" = "$BUYER_EMAIL"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "SELECT email, role, status FROM users WHERE email = '${BUYER_EMAIL}';" > /tmp/buyer_register_success_db.txt
grep "${BUYER_EMAIL}" /tmp/buyer_register_success_db.txt
grep "BUYER" /tmp/buyer_register_success_db.txt
grep "ACTIVE" /tmp/buyer_register_success_db.txt

## Teardown
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE email = '${BUYER_EMAIL}';"
rm -f /tmp/buyer_register_success.json /tmp/buyer_register_success_status.txt /tmp/buyer_register_success_db.txt

# Success marker required by runner
echo "CODEVALID_TEST_ASSERTION_OK:buyer_register_success"
