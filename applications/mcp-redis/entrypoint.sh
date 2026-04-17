#!/bin/sh
set -eu

if [ -z "${MCP_REDIS_URL:-}" ]; then
  echo "[ERR] MCP_REDIS_URL is required" >&2
  exit 1
fi

exec mcp-redis
