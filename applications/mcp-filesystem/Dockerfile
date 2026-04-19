FROM ghcr.io/sparfenyuk/mcp-proxy:latest@sha256:644ae2eec70fccba8a1b49d75172bd6b298860aa8bbeae708ab2ab0b3bf88da8

ARG MCP_FILESYSTEM_VERSION=2026.1.14

RUN apk add --no-cache nodejs npm \
  && npm install --global --omit=dev "@modelcontextprotocol/server-filesystem@${MCP_FILESYSTEM_VERSION}" \
  && npm cache clean --force

COPY entrypoint.sh /usr/local/bin/mcp-filesystem-entrypoint

RUN chmod 0755 /usr/local/bin/mcp-filesystem-entrypoint

EXPOSE 8098
ENTRYPOINT ["catatonit", "--", "/usr/local/bin/mcp-filesystem-entrypoint"]
