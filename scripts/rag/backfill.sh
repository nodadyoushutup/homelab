#!/usr/bin/env bash
# Trigger rag-engine backfill: health check, optional y/n, POST /v1/backfill (async job).
# Progress and errors: rag-engine service logs (Dozzle/Graylog), GET /v1/backfill/status.
#
# Credentials: .config/scripts/rag.env (if present) or --base-url / --api-key.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RAG_ENV_FILE="${RAG_ENV_FILE:-${REPO_ROOT}/.config/scripts/rag.env}"

RAG_ENGINE_BASE_URL=""
RAG_ENGINE_API_KEY=""

AUTO_YES=0
DRY_RUN=0
PRUNE_ORPHANS_ONLY=0
DO_STATUS=0
DO_STOP=0

usage() {
  cat <<EOF
Usage: scripts/rag/backfill.sh [options]

  scripts/rag/backfill.sh --yes
  scripts/rag/backfill.sh --base-url https://rag-engine.example.com --api-key SECRET --yes
  scripts/rag/backfill.sh --dry-run
  scripts/rag/backfill.sh --status
  scripts/rag/backfill.sh --stop

Credentials (required unless set in .config/scripts/rag.env):
  --base-url URL         rag-engine base URL (no trailing slash)
  --api-key KEY          x-api-key (must match RAG_ENGINE_API_KEY on the service)

Options:
  --yes, -y              Skip confirmation prompt
  --dry-run              Count eligible files only (no writes)
  --prune-orphans-only   Orphan prune only (no indexing)
  --status               Show current job status
  --stop                 Request stop of active backfill
  -h, --help

Copy .config/scripts/rag.env.example to .config/scripts/rag.env and fill in values.
Override env file path with RAG_ENV_FILE.
EOF
}

log() { echo "[rag-backfill] $*"; }
die() { echo "[rag-backfill] ERROR: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

load_rag_env() {
  if [[ ! -f "$RAG_ENV_FILE" ]]; then
    return 0
  fi
  log "Loading ${RAG_ENV_FILE}"
  set -a
  # shellcheck disable=SC1090
  source "$RAG_ENV_FILE"
  set +a
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base-url)
        [[ $# -ge 2 ]] || die "--base-url requires a value"
        RAG_ENGINE_BASE_URL="$2"
        shift 2
        ;;
      --api-key)
        [[ $# -ge 2 ]] || die "--api-key requires a value"
        RAG_ENGINE_API_KEY="$2"
        shift 2
        ;;
      --yes|-y) AUTO_YES=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --prune-orphans-only) PRUNE_ORPHANS_ONLY=1; shift ;;
      --status) DO_STATUS=1; shift ;;
      --stop) DO_STOP=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1 (try --help)" ;;
    esac
  done
}

require_credentials() {
  if [[ -n "$RAG_ENGINE_BASE_URL" && -n "$RAG_ENGINE_API_KEY" ]]; then
    return 0
  fi
  die "RAG_ENGINE_BASE_URL and RAG_ENGINE_API_KEY are required — set .config/scripts/rag.env or pass --base-url and --api-key"
}

curl_api() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local url="${RAG_ENGINE_BASE_URL%/}${path}"
  local -a cmd=(
    curl -fsS -X "$method" "$url"
    -H "Content-Type: application/json"
    -H "x-api-key: ${RAG_ENGINE_API_KEY}"
  )
  if [[ -n "$data" ]]; then
    cmd+=(-d "$data")
  fi
  "${cmd[@]}"
}

check_reachable() {
  local url="${RAG_ENGINE_BASE_URL%/}/healthz"
  local code
  code="$(curl -fsS -o /dev/null -w "%{http_code}" "$url" -H "x-api-key: ${RAG_ENGINE_API_KEY}" 2>/dev/null || echo "000")"
  [[ "$code" == "200" ]] || die "rag-engine unreachable at ${RAG_ENGINE_BASE_URL} (healthz HTTP ${code})"
}

confirm_start() {
  if [[ "$AUTO_YES" == "1" || "$DRY_RUN" == "1" ]]; then
    return 0
  fi
  local answer
  read -r -p "Start RAG backfill on ${RAG_ENGINE_BASE_URL}? [Y/n] " answer
  answer="${answer,,}"
  [[ -z "$answer" || "$answer" == "y" || "$answer" == "yes" ]] || die "Cancelled."
}

build_backfill_json() {
  local confirm="false"
  if [[ "$DRY_RUN" == "1" ]]; then
    confirm="false"
  else
    confirm="true"
  fi
  cat <<EOF
{"confirm":${confirm},"dry_run":$( [[ "$DRY_RUN" == "1" ]] && echo true || echo false ),"prune_orphans_only":$( [[ "$PRUNE_ORPHANS_ONLY" == "1" ]] && echo true || echo false )}
EOF
}

main() {
  load_rag_env
  parse_args "$@"
  need_cmd curl
  require_credentials
  check_reachable

  if [[ "$DO_STATUS" == "1" ]]; then
    curl_api GET "/v1/backfill/status" | python3 -m json.tool
    exit 0
  fi

  if [[ "$DO_STOP" == "1" ]]; then
    curl_api POST "/v1/backfill/stop" "{}" | python3 -m json.tool
    exit 0
  fi

  confirm_start
  log "POST /v1/backfill"
  resp="$(curl_api POST "/v1/backfill" "$(build_backfill_json)")"
  echo "$resp" | python3 -m json.tool
  log "Job triggered. Watch rag-engine logs or re-run with --status."
}

main "$@"
