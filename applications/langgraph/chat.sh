#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${LANGCHAIN_AGENT_CHAT_APP_DIR:-${SCRIPT_DIR}/../langchain-agent-chat}"
HOST="${LANGCHAIN_AGENT_CHAT_HOST:-0.0.0.0}"
PORT="${LANGCHAIN_AGENT_CHAT_PORT:-3000}"
PUBLIC_API_URL="${LANGCHAIN_AGENT_CHAT_PUBLIC_API_URL:-}"
ASSISTANT_ID="${LANGCHAIN_AGENT_CHAT_ASSISTANT_ID:-langgraph}"
AUTH_SCHEME="${LANGCHAIN_AGENT_CHAT_AUTH_SCHEME:-}"
AGENT_SERVER_PORT="${AGENT_SERVER_PORT:-${LANGGRAPH_DEBUG_PORT:-2124}}"
LANGGRAPH_API_URL="${LANGCHAIN_AGENT_CHAT_LANGGRAPH_API_URL:-http://127.0.0.1:${AGENT_SERVER_PORT}}"
CLEAR_PORT="${LANGCHAIN_AGENT_CHAT_CLEAR_PORT:-1}"
PUBLIC_HOST="${LANGCHAIN_AGENT_CHAT_PUBLIC_HOST:-${LANGGRAPH_DEBUG_PUBLIC_HOST:-}}"

force_kill_port() {
  local target_port="$1"
  local pids=()

  if [[ -z "${target_port}" ]]; then
    return 0
  fi

  if command -v lsof >/dev/null 2>&1; then
    mapfile -t pids < <(lsof -tiTCP:"${target_port}" -sTCP:LISTEN 2>/dev/null || true)
  elif command -v fuser >/dev/null 2>&1; then
    mapfile -t pids < <(fuser -n tcp "${target_port}" 2>/dev/null | tr ' ' '\n' | awk 'NF' || true)
  fi

  if [[ "${#pids[@]}" -eq 0 ]]; then
    echo "  port ${target_port}: already free"
    return 0
  fi

  echo "  port ${target_port}: force-killing pid(s) ${pids[*]}"
  kill -9 "${pids[@]}" 2>/dev/null || true
  sleep 1

  if command -v lsof >/dev/null 2>&1 && lsof -tiTCP:"${target_port}" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "error: port ${target_port} is still in use after force-kill" >&2
    exit 1
  fi
}

if [[ ! -d "${APP_DIR}" ]]; then
  echo "error: langchain-agent-chat directory not found: ${APP_DIR}" >&2
  exit 1
fi

if [[ ! -f "${APP_DIR}/package.json" ]]; then
  echo "error: ${APP_DIR}/package.json is missing" >&2
  exit 1
fi

app_cmd=()

if [[ -x "${APP_DIR}/node_modules/.bin/next" ]]; then
  app_cmd=("${APP_DIR}/node_modules/.bin/next")
elif command -v pnpm >/dev/null 2>&1; then
  app_cmd=("pnpm" "exec" "next")
elif command -v corepack >/dev/null 2>&1; then
  app_cmd=("corepack" "pnpm" "exec" "next")
fi

if [[ "${#app_cmd[@]}" -eq 0 ]]; then
  echo "error: langchain-agent-chat dev command not found. Install dependencies in ${APP_DIR} first." >&2
  exit 1
fi

if [[ -z "${PUBLIC_HOST}" ]]; then
  PUBLIC_HOST="$(
    ip route get 1.1.1.1 2>/dev/null |
      awk '/src/ { for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }'
  )"
fi

LOCAL_HOST_DISPLAY="$([[ "${HOST}" == "0.0.0.0" ]] && echo "127.0.0.1" || echo "${HOST}")"

if [[ -z "${PUBLIC_API_URL}" ]]; then
  PUBLIC_API_URL="http://${PUBLIC_HOST:-${LOCAL_HOST_DISPLAY}}:${PORT}/api"
fi

echo "LangChain Agent Chat dev server"
echo "  app: ${APP_DIR}"
echo "  local: http://${LOCAL_HOST_DISPLAY}:${PORT}"
if [[ -n "${PUBLIC_HOST}" ]]; then
  echo "  lan:  http://${PUBLIC_HOST}:${PORT}"
fi
echo "  assistant: ${ASSISTANT_ID}"
echo "  proxy api: ${PUBLIC_API_URL}"
echo "  langgraph upstream: ${LANGGRAPH_API_URL}"

if [[ "${CLEAR_PORT}" == "1" ]]; then
  echo "  cleanup port: ${PORT}"
  force_kill_port "${PORT}"
fi

app_args=(
  "${app_cmd[@]}"
  dev
  --hostname
  "${HOST}"
  --port
  "${PORT}"
)

cd "${APP_DIR}"
export HOSTNAME="${HOST}"
export PORT="${PORT}"
export NEXT_PUBLIC_API_URL="${PUBLIC_API_URL}"
export NEXT_PUBLIC_ASSISTANT_ID="${ASSISTANT_ID}"
export NEXT_PUBLIC_AUTH_SCHEME="${AUTH_SCHEME}"
export LANGGRAPH_API_URL="${LANGGRAPH_API_URL}"
export NEXT_TELEMETRY_DISABLED=1
exec "${app_args[@]}"
