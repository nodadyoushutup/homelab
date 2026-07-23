FROM ghcr.io/sparfenyuk/mcp-proxy:latest@sha256:ce037447191eeed517faa80640539dedaffb79a3ec107bfd23625a4438b0d06d

RUN apk add --no-cache nodejs npm \
  && npm install --global --omit=dev @thelord/mcp-cloudflare@1.6.0 \
  && npm cache clean --force

COPY entrypoint.sh /usr/local/bin/mcp-cloudflare-entrypoint

RUN chmod 0755 /usr/local/bin/mcp-cloudflare-entrypoint /usr/local/bin/mcp-cloudflare

EXPOSE 8084
ENTRYPOINT ["catatonit", "--", "/usr/local/bin/mcp-cloudflare-entrypoint"]
