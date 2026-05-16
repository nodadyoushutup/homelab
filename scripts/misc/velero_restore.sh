#!/usr/bin/env bash
# Wholesale restore of a Velero backup by name (namespace + snapshotMoveData volumes from MinIO/Kopia).
#
# Usage:
#   scripts/misc/velero_restore.sh radarr-nightly-20260516030000
#   scripts/misc/velero_restore.sh -y radarr-manual-movedata-test
#   scripts/misc/velero_restore.sh --wait clusterplex-nightly-20260516224837
#
# Environment:
#   VELERO_NAMESPACE=velero
#   VELERO_RESTORE_YES=1          # skip confirmation (same as -y)

set -euo pipefail

VELERO_NAMESPACE="${VELERO_NAMESPACE:-velero}"
ASSUME_YES="${VELERO_RESTORE_YES:-0}"
WAIT_FOR_COMPLETE=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] <backup-name>

Restore all resources (and moved PVC data) from a completed Velero backup.

Options:
  -y, --yes     Skip confirmation prompt
  --wait        Block until restore phase is Completed or Failed
  -h, --help    Show this help

Examples:
  $(basename "$0") radarr-nightly-20260516030000
  $(basename "$0") -y --wait clusterplex-nightly-20260516224837

List backups:
  kubectl get backups -n ${VELERO_NAMESPACE}
EOF
}

log() { echo "[INFO] $*"; }
err() { echo "[ERR] $*" >&2; }

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Missing required command: $1"
    exit 1
  fi
}

parse_args() {
  BACKUP_NAME=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y | --yes)
        ASSUME_YES=1
        shift
        ;;
      --wait)
        WAIT_FOR_COMPLETE=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      -*)
        err "Unknown option: $1"
        usage >&2
        exit 1
        ;;
      *)
        if [[ -n "${BACKUP_NAME}" ]]; then
          err "Unexpected argument: $1 (only one backup name allowed)"
          exit 1
        fi
        BACKUP_NAME="$1"
        shift
        ;;
    esac
  done

  if [[ -z "${BACKUP_NAME}" ]]; then
    err "Missing backup name."
    usage >&2
    exit 1
  fi
}

backup_info() {
  kubectl -n "${VELERO_NAMESPACE}" get backup "${BACKUP_NAME}" -o json 2>/dev/null
}

print_backup_summary() {
  local phase storage ttl snap_move
  phase="$(kubectl -n "${VELERO_NAMESPACE}" get backup "${BACKUP_NAME}" -o jsonpath='{.status.phase}')"
  storage="$(kubectl -n "${VELERO_NAMESPACE}" get backup "${BACKUP_NAME}" -o jsonpath='{.spec.storageLocation}')"
  ttl="$(kubectl -n "${VELERO_NAMESPACE}" get backup "${BACKUP_NAME}" -o jsonpath='{.spec.ttl}')"
  snap_move="$(kubectl -n "${VELERO_NAMESPACE}" get backup "${BACKUP_NAME}" -o jsonpath='{.spec.snapshotMoveData}')"
  local namespaces
  namespaces="$(kubectl -n "${VELERO_NAMESPACE}" get backup "${BACKUP_NAME}" -o jsonpath='{.spec.includedNamespaces[*]}')"

  log "Backup:          ${BACKUP_NAME}"
  log "Phase:           ${phase:-unknown}"
  log "Storage location: ${storage:-default}"
  log "Namespaces:      ${namespaces:-<from backup metadata>}"
  log "snapshotMoveData: ${snap_move:-false}"
  log "TTL:             ${ttl:-<unset>}"
}

confirm_restore() {
  if [[ "${ASSUME_YES}" == "1" ]]; then
    return 0
  fi

  echo ""
  echo "This will restore the FULL backup into the cluster (existing resources may be updated or conflict)."
  echo "Large restores (e.g. Radarr ~80GB) can take hours."
  read -r -p "Proceed with restore of '${BACKUP_NAME}'? [y/N] " reply
  case "${reply}" in
    y | Y | yes | YES) ;;
    *)
      echo "Aborted."
      exit 0
      ;;
  esac
}

restore_name_for_backup() {
  local base="restore-${BACKUP_NAME}"
  # Kubernetes object name max length 63
  if ((${#base} <= 63)); then
    echo "${base}"
    return
  fi
  echo "restore-$(date -u +%Y%m%d%H%M%S)"
}

create_restore() {
  RESTORE_NAME="$(restore_name_for_backup)"

  if kubectl -n "${VELERO_NAMESPACE}" get restore "${RESTORE_NAME}" >/dev/null 2>&1; then
    err "Restore ${RESTORE_NAME} already exists. Delete it or pick another backup."
    exit 1
  fi

  log "Creating Restore ${RESTORE_NAME} from backup ${BACKUP_NAME} ..."

  kubectl apply -f - <<EOF
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: ${RESTORE_NAME}
  namespace: ${VELERO_NAMESPACE}
  labels:
    homelab.nodadyoushutup.com/restore-from: ${BACKUP_NAME}
spec:
  backupName: ${BACKUP_NAME}
EOF
}

watch_restore() {
  log "Watching restore (poll every 30s; Ctrl+C stops watching — restore continues) ..."
  local deadline=$((SECONDS + 7200))
  while true; do
    local phase
    phase="$(kubectl -n "${VELERO_NAMESPACE}" get restore "${RESTORE_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")"
    echo "--- $(date -u +%H:%M:%S) phase=${phase:-Pending} ---"
    kubectl -n "${VELERO_NAMESPACE}" get datadownloads -l "velero.io/restore-name=${RESTORE_NAME}" \
      -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,BYTES:.status.progress.bytesDone,TOTAL:.status.progress.totalBytes \
      2>/dev/null | head -20 || true

    if [[ "${phase}" == "Completed" ]]; then
      log "Restore completed successfully."
      return 0
    fi
    if [[ "${phase}" == "Failed" || "${phase}" == "PartiallyFailed" ]]; then
      err "Restore ended with phase: ${phase}"
      kubectl -n "${VELERO_NAMESPACE}" describe restore "${RESTORE_NAME}" | tail -40 >&2 || true
      exit 1
    fi
    if (( SECONDS > deadline )); then
      err "Timed out after 2h. Check: kubectl describe restore -n ${VELERO_NAMESPACE} ${RESTORE_NAME}"
      exit 1
    fi
    sleep 30
  done
}

main() {
  parse_args "$@"
  require_command kubectl

  if ! backup_info >/dev/null; then
    err "Backup not found: ${VELERO_NAMESPACE}/${BACKUP_NAME}"
    echo "List backups: kubectl get backups -n ${VELERO_NAMESPACE}" >&2
    exit 1
  fi

  local phase
  phase="$(kubectl -n "${VELERO_NAMESPACE}" get backup "${BACKUP_NAME}" -o jsonpath='{.status.phase}')"
  if [[ "${phase}" != "Completed" ]]; then
    err "Backup phase is '${phase}', not Completed. Restore may fail or be incomplete."
    if [[ "${ASSUME_YES}" != "1" ]]; then
      read -r -p "Continue anyway? [y/N] " reply
      case "${reply}" in
        y | Y | yes | YES) ;;
        *) exit 1 ;;
      esac
    fi
  fi

  print_backup_summary
  confirm_restore
  create_restore

  log "Restore object created: ${VELERO_NAMESPACE}/${RESTORE_NAME}"
  log "Monitor: kubectl get restore -n ${VELERO_NAMESPACE} ${RESTORE_NAME} -w"
  log "Data:    kubectl get datadownloads -n ${VELERO_NAMESPACE} -l velero.io/restore-name=${RESTORE_NAME} -o wide -w"

  if [[ "${WAIT_FOR_COMPLETE}" == "1" ]]; then
    watch_restore
  else
    log "Not waiting (--wait to block until done)."
  fi
}

main "$@"
