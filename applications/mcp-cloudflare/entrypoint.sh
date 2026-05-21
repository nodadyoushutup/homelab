#!/bin/sh
set -eu

if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  echo "[ERR] CLOUDFLARE_API_TOKEN is required" >&2
  exit 1
fi

if [ -z "${CLOUDFLARE_ZONE_ID:-}" ]; then
  echo "[ERR] CLOUDFLARE_ZONE_ID is required" >&2
  exit 1
fi

exec /app/.venv/bin/mcp-proxy \
  --host "${MCP_CLOUDFLARE_HOST:-0.0.0.0}" \
  --port "${MCP_CLOUDFLARE_LISTEN_PORT:-8084}" \
  --stateless \
  --pass-environment \
  -- \
  /usr/local/bin/mcp-cloudflare
