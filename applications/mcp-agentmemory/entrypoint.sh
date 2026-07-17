#!/bin/sh
set -eu

if [ -z "${AGENTMEMORY_URL:-}" ]; then
  echo "[ERR] AGENTMEMORY_URL is required (e.g. http://agentmemory:3111)" >&2
  exit 1
fi

if [ -z "${AGENTMEMORY_SECRET:-}" ]; then
  echo "[ERR] AGENTMEMORY_SECRET is required" >&2
  exit 1
fi

if [ -z "${MCP_AGENTMEMORY_API_KEY:-}" ]; then
  echo "[ERR] MCP_AGENTMEMORY_API_KEY is required" >&2
  exit 1
fi

LISTEN_PORT="${MCP_AGENTMEMORY_LISTEN_PORT:-8087}"
UPSTREAM_PORT="${MCP_AGENTMEMORY_UPSTREAM_PORT:-18087}"
export MCP_AGENTMEMORY_UPSTREAM="http://127.0.0.1:${UPSTREAM_PORT}"
export MCP_AGENTMEMORY_HOST="${MCP_AGENTMEMORY_HOST:-0.0.0.0}"
export MCP_AGENTMEMORY_LISTEN_PORT="${LISTEN_PORT}"

/app/.venv/bin/mcp-proxy \
  --transport streamablehttp \
  --host 127.0.0.1 \
  --port "${UPSTREAM_PORT}" \
  --stateless \
  --pass-environment \
  -- \
  agentmemory-mcp &
MCP_PROXY_PID=$!

cleanup() {
  kill "${MCP_PROXY_PID}" 2>/dev/null || true
  wait "${MCP_PROXY_PID}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

/app/.venv/bin/python - <<PY
import socket
import time
port = int("${UPSTREAM_PORT}")
for _ in range(60):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=1.0):
            break
    except OSError:
        time.sleep(0.5)
else:
    raise SystemExit("mcp-proxy did not become ready on 127.0.0.1:%s" % port)
PY

exec /app/.venv/bin/python /usr/local/lib/mcp-agentmemory/auth_gateway.py
