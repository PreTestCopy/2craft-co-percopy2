#!/usr/bin/env bash
# .codevalid/entrypoint.sh
set -euo pipefail

# 1. Wait for each dependency *through toxiproxy*
for hp in ${WAIT_FOR_TCP:-}; do
  host="${hp%%:*}"; port="${hp##*:}"
  echo "waiting for ${host}:${port} ..."
  until nc -z "$host" "$port"; do sleep 1; done
done

# 2. Run migrations (Prisma skill: npx prisma migrate deploy through toxiproxy)
${MIGRATE_CMD:-true}

# 3. Hand off to the real server on 6713
exec "$@"
