FROM node:22.14-slim

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

# §3.3 Dependency manifest first for layer caching
# Prisma 7 skill: npm ci --ignore-scripts
COPY package.json ./
RUN npm install --ignore-scripts

# §3.4 step 4: full source copy (includes prisma/schema.prisma, prisma.config.ts, tsconfig*.json)
COPY . .

# §3.4 step 5: Prisma 7 codegen — before compile, never || true
RUN npx prisma generate

# §3.4 step 6: compile
RUN npm run build

EXPOSE 6713

COPY .codevalid/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["node", "dist/index.js"]
