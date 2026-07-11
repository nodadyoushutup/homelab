#!/usr/bin/env bash
# Toggle all qBittorrent overlays through Git, then sync the changed Argo CD apps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OVERLAYS_DIR="${REPO_ROOT}/kubernetes/qbittorrent/overlays"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") up [--dry-run]
  $(basename "$0") down [--force] [--dry-run]

Commands:
  up            Set every qBittorrent overlay to one replica.
  down          Keep only the highest movie-N, highest television-N, and movie-4k
                online; set every other overlay to zero replicas.
  down --force  Set every qBittorrent overlay to zero replicas.

The script commits only changed qBittorrent replica patches, pushes the current
branch, hard-refreshes the matching Argo CD Applications, and requests a sync.
EOF
}

log() {
  printf '[qbittorrent-argocd] %s\n' "$*"
}

die() {
  printf '[qbittorrent-argocd] error: %s\n' "$*" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || die "git is required"
command -v awk >/dev/null 2>&1 || die "awk is required"

[[ "$#" -ge 1 ]] || {
  usage >&2
  exit 2
}

action="$1"
shift
force=0
dry_run=0

case "${action}" in
  up|down) ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    die "first argument must be up or down"
    ;;
esac

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --force)
      force=1
      ;;
    --dry-run)
      dry_run=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
  shift
done

if [[ "${force}" -eq 1 && "${action}" != "down" ]]; then
  die "--force is valid only with down"
fi

if [[ "${dry_run}" -eq 0 ]]; then
  command -v kubectl >/dev/null 2>&1 || die "kubectl is required"
  if [[ -z "${KUBECONFIG:-}" && -f "${HOME}/.kube/homelab.config" ]]; then
    export KUBECONFIG="${HOME}/.kube/homelab.config"
  fi
  kubectl get namespace "${ARGOCD_NAMESPACE}" >/dev/null ||
    die "cannot access Argo CD namespace: ${ARGOCD_NAMESPACE}"
fi

cd "${REPO_ROOT}"
[[ -d "${OVERLAYS_DIR}" ]] || die "overlay directory not found: ${OVERLAYS_DIR}"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a Git repository: ${REPO_ROOT}"

dirty_overlays="$(git status --porcelain --untracked-files=no -- "${OVERLAYS_DIR}")"
if [[ -n "${dirty_overlays}" ]]; then
  printf '%s\n' "${dirty_overlays}" >&2
  die "qBittorrent overlays already contain uncommitted changes"
fi

shopt -s nullglob
patch_files=("${OVERLAYS_DIR}"/*/deployment-node-patch.yaml)
shopt -u nullglob
[[ "${#patch_files[@]}" -gt 0 ]] || die "no qBittorrent overlay patches found"

movie_peak=-1
television_peak=-1
for patch_file in "${patch_files[@]}"; do
  overlay="$(basename "$(dirname "${patch_file}")")"
  if [[ "${overlay}" =~ ^movie-([0-9]+)$ ]]; then
    number="${BASH_REMATCH[1]}"
    ((10#${number} > movie_peak)) && movie_peak=$((10#${number}))
  elif [[ "${overlay}" =~ ^television-([0-9]+)$ ]]; then
    number="${BASH_REMATCH[1]}"
    ((10#${number} > television_peak)) && television_peak=$((10#${number}))
  fi
done

[[ "${movie_peak}" -ge 0 ]] || die "no numbered movie overlays found"
[[ "${television_peak}" -ge 0 ]] || die "no numbered television overlays found"

desired_replicas() {
  local overlay="$1"

  if [[ "${action}" == "up" ]]; then
    printf '1\n'
    return
  fi

  if [[ "${force}" -eq 0 ]] && {
    [[ "${overlay}" == "movie-${movie_peak}" ]] ||
      [[ "${overlay}" == "television-${television_peak}" ]] ||
      [[ "${overlay}" == "movie-4k" ]]
  }; then
    printf '1\n'
    return
  fi

  printf '0\n'
}

set_replicas() {
  local patch_file="$1"
  local replicas="$2"
  local output_file

  output_file="$(mktemp)"
  awk -v replicas="${replicas}" '
    /^spec:[[:space:]]*$/ {
      print
      print "  replicas: " replicas
      in_spec = 1
      next
    }
    in_spec && /^  replicas:[[:space:]]*[0-9]+[[:space:]]*$/ {
      next
    }
    { print }
  ' "${patch_file}" >"${output_file}"

  if cmp -s "${patch_file}" "${output_file}"; then
    rm -f "${output_file}"
    return 1
  fi

  if [[ "${dry_run}" -eq 0 ]]; then
    chmod --reference="${patch_file}" "${output_file}"
    mv "${output_file}" "${patch_file}"
  else
    rm -f "${output_file}"
  fi
}

changed_files=()
changed_overlays=()
for patch_file in "${patch_files[@]}"; do
  overlay="$(basename "$(dirname "${patch_file}")")"
  replicas="$(desired_replicas "${overlay}")"
  if set_replicas "${patch_file}" "${replicas}"; then
    changed_files+=("${patch_file}")
    changed_overlays+=("${overlay}")
    log "${overlay}: replicas ${replicas}"
  fi
done

if [[ "${#changed_files[@]}" -eq 0 ]]; then
  log "desired replica state is already present; nothing to commit or sync"
  exit 0
fi

if [[ "${dry_run}" -eq 1 ]]; then
  log "dry-run: would change, commit, push, and sync ${#changed_files[@]} overlay(s)"
  exit 0
fi

git add -- "${changed_files[@]}"

if [[ "${action}" == "up" ]]; then
  commit_message="qbittorrent: scale all instances up"
elif [[ "${force}" -eq 1 ]]; then
  commit_message="qbittorrent: force all instances down"
else
  commit_message="qbittorrent: scale down to latest instances"
fi

git commit -m "${commit_message}" -- "${changed_files[@]}"
git push
pushed_revision="$(git rev-parse HEAD)"
log "pushed ${pushed_revision:0:12}"

for overlay in "${changed_overlays[@]}"; do
  app="qbittorrent-${overlay}"
  kubectl annotate application -n "${ARGOCD_NAMESPACE}" "${app}" \
    argocd.argoproj.io/refresh=hard --overwrite >/dev/null
done

for overlay in "${changed_overlays[@]}"; do
  app="qbittorrent-${overlay}"
  sync_patch="$(printf \
    '{"operation":{"sync":{"revision":"%s","syncStrategy":{"hook":{}}}}}' \
    "${pushed_revision}")"
  kubectl patch application -n "${ARGOCD_NAMESPACE}" "${app}" \
    --type merge --patch "${sync_patch}" >/dev/null
  log "sync requested: ${app}"
done

log "finished ${action}; synced ${#changed_overlays[@]} Argo CD application(s)"
