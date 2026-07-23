# Streamable HTTP gateway for agentmemory: mcp-proxy + x-api-key front door.
FROM ghcr.io/sparfenyuk/mcp-proxy:latest@sha256:ce037447191eeed517faa80640539dedaffb79a3ec107bfd23625a4438b0d06d

RUN apk add --no-cache nodejs npm \
  && npm install --global --omit=dev @agentmemory/mcp@0.9.27 \
  && npm cache clean --force

COPY auth_gateway.py /usr/local/lib/mcp-agentmemory/auth_gateway.py
COPY entrypoint.sh /usr/local/bin/mcp-agentmemory-entrypoint

RUN chmod 0755 /usr/local/bin/mcp-agentmemory-entrypoint \
  && chmod 0644 /usr/local/lib/mcp-agentmemory/auth_gateway.py

EXPOSE 8087
ENTRYPOINT ["catatonit", "--", "/usr/local/bin/mcp-agentmemory-entrypoint"]
