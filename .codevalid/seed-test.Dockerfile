FROM debian:bookworm-slim

ARG CACHEBUST=1

# Install curl, jq, ca-certificates, bash, and psql (postgres skill: psql from postgres:16 compatible client)
RUN echo "cachebust=${CACHEBUST}" \
    && apt-get update && apt-get install -y --no-install-recommends \
        curl \
        jq \
        ca-certificates \
        bash \
        postgresql-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

COPY seed_test_cases ./seed_test_cases
COPY tests ./tests
