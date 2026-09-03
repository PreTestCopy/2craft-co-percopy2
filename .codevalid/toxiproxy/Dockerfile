FROM ghcr.io/shopify/toxiproxy:2.12.0
# The base is FROM scratch — no shell or HTTP client.
# Add static busybox for the healthcheck to probe the admin API.
COPY --from=busybox:1.38-musl /bin/busybox /bin/busybox
COPY toxiproxy.json /config/toxiproxy.json
