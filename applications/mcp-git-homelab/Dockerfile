FROM ghcr.io/sparfenyuk/mcp-proxy:latest@sha256:644ae2eec70fccba8a1b49d75172bd6b298860aa8bbeae708ab2ab0b3bf88da8

ARG MCP_GIT_VERSION=2026.1.14

RUN apk add --no-cache git py3-pip \
  && /usr/bin/python3 -m pip install --no-cache-dir --break-system-packages "mcp-server-git==${MCP_GIT_VERSION}"

COPY entrypoint.sh /usr/local/bin/mcp-git-homelab-entrypoint

RUN chmod 0755 /usr/local/bin/mcp-git-homelab-entrypoint

EXPOSE 8099
ENTRYPOINT ["catatonit", "--", "/usr/local/bin/mcp-git-homelab-entrypoint"]
