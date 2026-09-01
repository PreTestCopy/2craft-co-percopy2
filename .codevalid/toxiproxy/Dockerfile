FROM ghcr.io/shopify/toxiproxy:2.12.0
# Base is FROM scratch — only /toxiproxy binary, no shell or HTTP client.
# Add static busybox for healthcheck to probe the admin API.
COPY --from=busybox:1.38-musl /bin/busybox /bin/busybox
COPY toxiproxy.json /config/toxiproxy.json
