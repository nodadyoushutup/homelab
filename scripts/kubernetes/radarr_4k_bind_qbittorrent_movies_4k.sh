#!/usr/bin/env bash
# Point radarr-4k at qbittorrent-movie-4k as its only download client.
set -euo pipefail

NS="${NS:-radarr-4k}"
PG="${PG:-radarr-4k-postgres}"
DB_USER="${DB_USER:-radarr4k}"
DB_NAME="${DB_NAME:-radarr4k-main}"
QBIT_HOST="${QBIT_HOST:-qbittorrent.qbittorrent-movie-4k.svc.cluster.local}"
QBIT_PORT="${QBIT_PORT:-8080}"
QBIT_USER="${QBIT_USER:-admin}"
QBIT_PASS="${QBIT_PASS:-S#nvhs89vher}"

SETTINGS=$(cat <<EOF
{"host": "${QBIT_HOST}", "port": ${QBIT_PORT}, "useSsl": false, "urlBase": "", "username": "${QBIT_USER}", "password": "${QBIT_PASS}", "movieCategory": "radarr", "recentMoviePriority": 0, "olderMoviePriority": 0, "initialState": 0, "sequentialOrder": false, "firstAndLast": false, "contentLayout": 0}
EOF
)

kubectl exec -n "${NS}" "deploy/${PG}" -- \
  psql -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 \
  -c "UPDATE \"DownloadClients\" SET \"Name\" = 'qBittorrent Movies 4K', \"Settings\" = '${SETTINGS}' WHERE \"Id\" = (SELECT MIN(\"Id\") FROM \"DownloadClients\");"

kubectl exec -n "${NS}" "deploy/${PG}" -- \
  psql -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 \
  -c "DELETE FROM \"DownloadClientStatus\"; DELETE FROM \"DownloadClients\" WHERE \"Id\" <> (SELECT MIN(\"Id\") FROM \"DownloadClients\");"

echo "[radarr-4k] Download clients:"
kubectl exec -n "${NS}" "deploy/${PG}" -- \
  psql -U "${DB_USER}" -d "${DB_NAME}" -At \
  -c "SELECT \"Id\" || ': ' || \"Name\" || ' -> ' || (\"Settings\"::json->>'host') FROM \"DownloadClients\";"

kubectl rollout restart -n "${NS}" deploy/radarr-4k
