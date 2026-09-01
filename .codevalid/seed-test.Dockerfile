FROM postgres:16
# postgres:16 ships psql — use it as the seed-test base so DB scripts work
# Also install curl, jq, ca-certificates, bash for HTTP assertions
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        jq \
        ca-certificates \
        bash \
    && rm -rf /var/lib/apt/lists/*

ARG CACHEBUST=1
RUN echo "cachebust=${CACHEBUST}"

WORKDIR /work
COPY seed_test_cases ./seed_test_cases
COPY tests ./tests
# Copy _infra.sh so test scripts can `source .codevalid/_infra.sh` from /work
COPY _infra.sh ./.codevalid/_infra.sh
