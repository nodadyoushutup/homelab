# Upstream: https://codeberg.org/anriha/qbittorrent-metrics-exporter (crates.io 0.3.2)
FROM rust:1.86-bookworm AS builder

ARG QBME_VERSION=0.3.2

RUN apt-get update \
    && apt-get install -y --no-install-recommends pkg-config libssl-dev \
    && rm -rf /var/lib/apt/lists/*

RUN cargo install qbittorrent-metrics-exporter --version "${QBME_VERSION}" --locked

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates wget \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/cargo/bin/qbittorrent-metrics-exporter /usr/local/bin/qbittorrent-metrics-exporter
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD wget --spider --quiet http://127.0.0.1:8000/metrics || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# Dev: Rust toolchain + crates.io binary; bind-mount upstream at /src to iterate on exporter source.
FROM rust:1.86-bookworm AS dev

ARG QBME_VERSION=0.3.2

RUN apt-get update \
    && apt-get install -y --no-install-recommends pkg-config libssl-dev ca-certificates wget \
    && rm -rf /var/lib/apt/lists/*

RUN cargo install qbittorrent-metrics-exporter --version "${QBME_VERSION}" --locked

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY dev-run.sh /usr/local/bin/dev-run.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/dev-run.sh

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD wget --spider --quiet http://127.0.0.1:8000/metrics || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/local/bin/dev-run.sh"]
