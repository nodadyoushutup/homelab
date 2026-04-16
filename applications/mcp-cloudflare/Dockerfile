FROM ghcr.io/sparfenyuk/mcp-proxy:latest@sha256:644ae2eec70fccba8a1b49d75172bd6b298860aa8bbeae708ab2ab0b3bf88da8

RUN apk add --no-cache nodejs npm \
  && npm install --global --omit=dev @thelord/mcp-cloudflare@1.6.0 \
  && npm cache clean --force

COPY entrypoint.sh /usr/local/bin/mcp-cloudflare-entrypoint

RUN chmod 0755 /usr/local/bin/mcp-cloudflare-entrypoint /usr/local/bin/mcp-cloudflare

EXPOSE 8084
ENTRYPOINT ["catatonit", "--", "/usr/local/bin/mcp-cloudflare-entrypoint"]
