# Streamable HTTP gateway for agentmemory: mcp-proxy + x-api-key front door.
FROM ghcr.io/sparfenyuk/mcp-proxy:latest@sha256:644ae2eec70fccba8a1b49d75172bd6b298860aa8bbeae708ab2ab0b3bf88da8

RUN apk add --no-cache nodejs npm \
  && npm install --global --omit=dev @agentmemory/mcp@0.9.27 \
  && npm cache clean --force

COPY auth_gateway.py /usr/local/lib/mcp-agentmemory/auth_gateway.py
COPY entrypoint.sh /usr/local/bin/mcp-agentmemory-entrypoint

RUN chmod 0755 /usr/local/bin/mcp-agentmemory-entrypoint \
  && chmod 0644 /usr/local/lib/mcp-agentmemory/auth_gateway.py

EXPOSE 8087
ENTRYPOINT ["catatonit", "--", "/usr/local/bin/mcp-agentmemory-entrypoint"]
