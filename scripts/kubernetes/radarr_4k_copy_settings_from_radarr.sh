#!/usr/bin/env bash
# One-shot: copy Radarr settings tables from radarr -> radarr-4k Postgres.
# Skips movies, files, history, and root paths. Safe to re-run (truncates copied tables first).
set -euo pipefail

SRC_NS="${SRC_NS:-radarr}"
DST_NS="${DST_NS:-radarr-4k}"
SRC_PG="${SRC_PG:-radarr-postgres}"
DST_PG="${DST_PG:-radarr-4k-postgres}"

SKIP_TABLES=(
  Movies MovieFiles MovieMetadata MovieTranslations
  RootFolders RemotePathMappings
  History DownloadHistory Blocklist PendingReleases
  AlternativeTitles Credits ExtraFiles SubtitleFiles
  ImportListMovies Collections Commands
)

psql_src() {
  kubectl exec -n "${SRC_NS}" "deploy/${SRC_PG}" -- \
    psql -U radarr -d radarr-main -v ON_ERROR_STOP=1 -At "$@"
}

psql_dst() {
  kubectl exec -n "${DST_NS}" "deploy/${DST_PG}" -- \
    psql -U radarr4k -d radarr4k-main -v ON_ERROR_STOP=1 "$@"
}

echo "[radarr-4k] Waiting for source and destination Postgres..."
kubectl wait -n "${SRC_NS}" --for=condition=available "deploy/${SRC_PG}" --timeout=300s
kubectl wait -n "${DST_NS}" --for=condition=available "deploy/${DST_PG}" --timeout=300s

echo "[radarr-4k] Waiting for Radarr 4K schema (start radarr-4k once if this hangs)..."
for _ in $(seq 1 60); do
  if psql_dst -c "SELECT 1 FROM \"Config\" LIMIT 1" >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

mapfile -t ALL_TABLES < <(psql_src -c \
  "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename")

should_skip() {
  local t="$1"
  local s
  for s in "${SKIP_TABLES[@]}"; do
    [[ "${t}" == "${s}" ]] && return 0
  done
  return 1
}

for table in "${ALL_TABLES[@]}"; do
  if should_skip "${table}"; then
    echo "[radarr-4k] skip ${table}"
    continue
  fi
  echo "[radarr-4k] copy ${table}"
  psql_dst -c "TRUNCATE TABLE \"${table}\" CASCADE"
  kubectl exec -n "${SRC_NS}" "deploy/${SRC_PG}" -- \
    pg_dump -U radarr -d radarr-main --data-only --table="\"${table}\"" \
    | kubectl exec -i -n "${DST_NS}" "deploy/${DST_PG}" -- \
      psql -U radarr4k -d radarr4k-main -v ON_ERROR_STOP=1
done

echo "[radarr-4k] Done. Restart radarr-4k deployment if the UI looks stale."
kubectl rollout restart -n "${DST_NS}" deploy/radarr-4k
