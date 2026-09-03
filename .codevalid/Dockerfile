FROM node:22.14-bookworm-slim

# §3.2 Common tooling layer
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        bash \
        netcat-openbsd \
        jq \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV PORT=6713

# §3.3 Install dependencies first (cache layer)
# postinstall runs prisma generate — skip it here; we run it explicitly after COPY
COPY package.json ./
RUN npm install --ignore-scripts

# §3.4 Copy application source, schema, configs
COPY . .

# Prisma skill: generate after COPY source, before build
RUN npx prisma generate

# §3.4 step 6: compile TypeScript
RUN npm run build

EXPOSE 6713

# §3.6 entrypoint handles wait-for-deps + migrate + exec
# .codevalid/entrypoint.sh is already present via COPY . . above
RUN chmod +x /app/.codevalid/entrypoint.sh

ENTRYPOINT ["/app/.codevalid/entrypoint.sh"]
CMD ["node", "dist/index.js"]
