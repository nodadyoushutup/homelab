#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-serve}"
shift || true

case "${cmd}" in
  serve)
    exec gunicorn \
      --bind "${HOST:-0.0.0.0}:${PORT:-8080}" \
      --workers "${GUNICORN_WORKERS:-2}" \
      --threads "${GUNICORN_THREADS:-4}" \
      --timeout "${GUNICORN_TIMEOUT:-120}" \
      'torrent_manager.app:create_app()'
    ;;
  dev)
    exec python -m torrent_manager "$@"
    ;;
  healthcheck)
    exec python -m torrent_manager healthcheck "$@"
    ;;
  *)
    echo "usage: torrent-manager-entrypoint {serve|dev|healthcheck}" >&2
    exit 1
    ;;
esac
