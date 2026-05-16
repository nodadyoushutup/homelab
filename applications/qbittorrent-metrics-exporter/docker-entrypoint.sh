#!/bin/sh
set -eu

startup_delay="${STARTUP_DELAY_SECONDS:-300}"
if [ "$startup_delay" -gt 0 ] 2>/dev/null; then
  echo "qbittorrent-metrics-exporter: sleeping ${startup_delay}s before start"
  sleep "$startup_delay"
fi

if [ "${QBITTORRENT_WAIT_FOR_LOGIN:-1}" = "1" ] && [ -n "${QBITTORRENT_HOSTS:-}" ]; then
  echo "qbittorrent-metrics-exporter: waiting for qBittorrent Web UI logins"
  pass="${QBITTORRENT_PASSWORD:-}"
  user="${QBITTORRENT_USERNAME:-admin}"
  # QBITTORRENT_HOSTS entries look like name=https://host.example.com
  while :; do
    fail=0
    for entry in $(printf '%s' "$QBITTORRENT_HOSTS" | tr ',' ' '); do
      url="${entry#*=}"
      case "$url" in
        http://*|https://*) ;;
        *) continue ;;
      esac
      body=$(wget -qO- --no-check-certificate \
        --post-data="username=${user}&password=${pass}" \
        "${url}/api/v2/auth/login" 2>/dev/null || true)
      if [ "$body" != "Ok." ]; then
        fail=$((fail + 1))
      fi
    done
    if [ "$fail" -eq 0 ]; then
      echo "qbittorrent-metrics-exporter: all instances accept login"
      break
    fi
    echo "qbittorrent-metrics-exporter: ${fail} instance(s) not ready; retrying in 30s"
    sleep 30
  done
fi

exec qbittorrent-metrics-exporter "$@"
