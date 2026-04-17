FROM ghcr.io/sparfenyuk/mcp-proxy:latest@sha256:644ae2eec70fccba8a1b49d75172bd6b298860aa8bbeae708ab2ab0b3bf88da8

ARG LANGFLOW_MCP_SERVER_VERSION=3.1.1

RUN apk add --no-cache nodejs npm \
  && npm install --global --omit=dev "langflow-mcp-server@${LANGFLOW_MCP_SERVER_VERSION}" \
  && npm cache clean --force

COPY entrypoint.sh /usr/local/bin/mcp-langflow-entrypoint

RUN chmod 0755 /usr/local/bin/mcp-langflow-entrypoint /usr/local/bin/langflow-mcp-server

EXPOSE 8102
ENTRYPOINT ["catatonit", "--", "/usr/local/bin/mcp-langflow-entrypoint"]
