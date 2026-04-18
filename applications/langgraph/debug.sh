#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${LANGGRAPH_APP_DIR:-${SCRIPT_DIR}/apps/controller-agent}"
HOST="${LANGGRAPH_DEBUG_HOST:-0.0.0.0}"
PORT="${LANGGRAPH_DEBUG_PORT:-2124}"
NO_RELOAD="${LANGGRAPH_DEBUG_NO_RELOAD:-0}"

if [[ ! -d "${APP_DIR}" ]]; then
  echo "error: app directory not found: ${APP_DIR}" >&2
  exit 1
fi

if [[ ! -f "${APP_DIR}/langgraph.json" ]]; then
  echo "error: ${APP_DIR}/langgraph.json is missing" >&2
  exit 1
fi

if [[ -x "${SCRIPT_DIR}/.venv/bin/langgraph" ]]; then
  LANGGRAPH_BIN="${SCRIPT_DIR}/.venv/bin/langgraph"
elif command -v langgraph >/dev/null 2>&1; then
  LANGGRAPH_BIN="$(command -v langgraph)"
else
  echo "error: langgraph CLI not found. Install dependencies first or provide applications/langgraph/.venv/bin/langgraph." >&2
  exit 1
fi

PUBLIC_HOST="${LANGGRAPH_DEBUG_PUBLIC_HOST:-}"
if [[ -z "${PUBLIC_HOST}" ]]; then
  PUBLIC_HOST="$(
    ip route get 1.1.1.1 2>/dev/null |
      awk '/src/ { for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }'
  )"
fi

export LANGGRAPH_CLI_NO_ANALYTICS="${LANGGRAPH_CLI_NO_ANALYTICS:-1}"

echo "LangGraph debug server"
echo "  app: ${APP_DIR}"
echo "  bind: http://${HOST}:${PORT}"
if [[ -n "${PUBLIC_HOST}" ]]; then
  echo "  lan:  http://${PUBLIC_HOST}:${PORT}"
fi
echo "  reload: $([[ "${NO_RELOAD}" == "1" ]] && echo disabled || echo enabled)"

cd "${APP_DIR}"

cmd=(
  "${LANGGRAPH_BIN}"
  dev
  --host
  "${HOST}"
  --port
  "${PORT}"
  --no-browser
)

if [[ "${NO_RELOAD}" == "1" ]]; then
  cmd+=(--no-reload)
fi

if [[ "$#" -gt 0 ]]; then
  cmd+=("$@")
fi

exec "${cmd[@]}"
