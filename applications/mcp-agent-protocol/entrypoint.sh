#!/bin/sh
set -eu

if [ -z "${MCP_AGENT_PROTOCOL_REDIS_URL:-}" ]; then
  echo "[ERR] MCP_AGENT_PROTOCOL_REDIS_URL is required" >&2
  exit 1
fi

exec mcp-agent-protocol
