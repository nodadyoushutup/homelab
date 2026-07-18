#!/bin/sh
set -eu

if [ -z "${JENKINS_URL:-}" ]; then
  echo "[ERR] JENKINS_URL is required" >&2
  exit 1
fi

if [ -z "${JENKINS_USERNAME:-}" ]; then
  echo "[ERR] JENKINS_USERNAME is required" >&2
  exit 1
fi

if [ -z "${JENKINS_PASSWORD:-}" ]; then
  echo "[ERR] JENKINS_PASSWORD is required" >&2
  exit 1
fi

exec mcp-jenkins \
  --transport streamable-http \
  --host "${MCP_JENKINS_HOST:-0.0.0.0}" \
  --port "${MCP_JENKINS_LISTEN_PORT:-9887}" \
  --jenkins-url "${JENKINS_URL}" \
  --jenkins-username "${JENKINS_USERNAME}" \
  --jenkins-password "${JENKINS_PASSWORD}" \
  ${MCP_JENKINS_READ_ONLY:+--read-only}
