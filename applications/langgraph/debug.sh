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

langgraph_cmd=()

if command -v langgraph >/dev/null 2>&1; then
  langgraph_candidate="$(command -v langgraph)"
  if "${langgraph_candidate}" --help >/dev/null 2>&1; then
    langgraph_cmd=("${langgraph_candidate}")
  fi
fi

if [[ "${#langgraph_cmd[@]}" -eq 0 && -x "${SCRIPT_DIR}/.venv/bin/langgraph" ]]; then
  if "${SCRIPT_DIR}/.venv/bin/langgraph" --help >/dev/null 2>&1; then
    langgraph_cmd=("${SCRIPT_DIR}/.venv/bin/langgraph")
  fi
fi

if [[ "${#langgraph_cmd[@]}" -eq 0 && -x "${SCRIPT_DIR}/.venv/bin/python" ]]; then
  if "${SCRIPT_DIR}/.venv/bin/python" -m langgraph_cli --help >/dev/null 2>&1; then
    langgraph_cmd=("${SCRIPT_DIR}/.venv/bin/python" "-m" "langgraph_cli")
  fi
fi

if [[ "${#langgraph_cmd[@]}" -eq 0 ]]; then
  echo "error: langgraph CLI not found. Install dependencies first or provide a working applications/langgraph/.venv/bin/python." >&2
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
export PYTHONPATH="${SCRIPT_DIR}/src${PYTHONPATH:+:${PYTHONPATH}}"

echo "LangGraph debug server"
echo "  app: ${APP_DIR}"
echo "  bind: http://${HOST}:${PORT}"
if [[ -n "${PUBLIC_HOST}" ]]; then
  echo "  lan:  http://${PUBLIC_HOST}:${PORT}"
fi
echo "  reload: $([[ "${NO_RELOAD}" == "1" ]] && echo disabled || echo enabled)"

cd "${APP_DIR}"

cmd=(
  "${langgraph_cmd[@]}"
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
