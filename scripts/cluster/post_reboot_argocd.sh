#!/usr/bin/env bash
# Recover Argo CD after an unclean cluster shutdown (power loss, node hard reset).
# Waits for the API and Flannel, replaces stuck argocd-repo-server pods, then
# hard-refreshes all Applications so sync/health reflect live cluster state.
#
# For ongoing recovery without manual runs, see kubernetes/argocd-management/
# argocd-repo-server-healer.yaml (CronJob every 5 minutes).
#
# Usage:
#   ./scripts/cluster/post_reboot_argocd.sh
#   ./scripts/cluster/post_reboot_argocd.sh --no-refresh
#   ./scripts/cluster/post_reboot_argocd.sh --dry-run
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
FLANNEL_NAMESPACE="${FLANNEL_NAMESPACE:-kube-system}"
FLANNEL_DAEMONSET="${FLANNEL_DAEMONSET:-kube-flannel}"
FLANNEL_LABEL_SELECTOR="${FLANNEL_LABEL_SELECTOR:-k8s-app=flannel}"
REPO_SERVER_LABEL="${REPO_SERVER_LABEL:-app.kubernetes.io/name=argocd-repo-server}"

CLUSTER_WAIT_ATTEMPTS="${CLUSTER_WAIT_ATTEMPTS:-60}"
CLUSTER_WAIT_SLEEP_SECONDS="${CLUSTER_WAIT_SLEEP_SECONDS:-5}"
FLANNEL_WAIT_TIMEOUT="${FLANNEL_WAIT_TIMEOUT:-10m}"
REPO_SERVER_ROLLOUT_TIMEOUT="${REPO_SERVER_ROLLOUT_TIMEOUT:-5m}"
REFRESH_APPS="${REFRESH_APPS:-1}"
DRY_RUN="${DRY_RUN:-0}"

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERR] $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Run after the Kubernetes cluster comes back from power loss or a hard reboot when
Argo CD Applications show Unknown sync or repo-server connection errors.

Options:
  --no-refresh   Repair repo-server only; do not annotate Applications for refresh.
  --dry-run      Print actions without changing the cluster.
  -h, --help     Show this help.
EOF
}

require_command() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "Missing required command: ${cmd}"
}

pick_kubeconfig() {
  if [[ -n "${KUBECONFIG:-}" ]]; then
    echo "${KUBECONFIG}"
    return 0
  fi

  if [[ -f "${HOME}/.kube/homelab.config" ]]; then
    echo "${HOME}/.kube/homelab.config"
    return 0
  fi

  echo "${HOME}/.kube/config"
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --no-refresh)
        REFRESH_APPS=0
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "Unknown argument: $1"
        ;;
    esac
  done
}

run_kubectl() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[DRY-RUN] kubectl $*"
    return 0
  fi
  kubectl "$@"
}

wait_for_cluster_api() {
  log "Waiting for Kubernetes API (kubeconfig: ${KUBECONFIG})"
  local attempt=1
  while (( attempt <= CLUSTER_WAIT_ATTEMPTS )); do
    if run_kubectl cluster-info >/dev/null 2>&1; then
      log "API is reachable"
      return 0
    fi
    warn "API not ready (${attempt}/${CLUSTER_WAIT_ATTEMPTS})"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      log "Dry-run: skipping API wait retries"
      return 0
    fi
    sleep "${CLUSTER_WAIT_SLEEP_SECONDS}"
    ((attempt++))
  done
  die "Timed out waiting for cluster API"
}

wait_for_flannel() {
  log "Waiting for CNI (${FLANNEL_NAMESPACE}/${FLANNEL_DAEMONSET})"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[DRY-RUN] kubectl -n ${FLANNEL_NAMESPACE} rollout status daemonset/${FLANNEL_DAEMONSET}"
    echo "[DRY-RUN] kubectl -n ${FLANNEL_NAMESPACE} wait --for=condition=ready pod -l ${FLANNEL_LABEL_SELECTOR}"
    return 0
  fi

  if ! kubectl -n "${FLANNEL_NAMESPACE}" get daemonset "${FLANNEL_DAEMONSET}" >/dev/null 2>&1; then
    warn "DaemonSet ${FLANNEL_NAMESPACE}/${FLANNEL_DAEMONSET} not found; waiting on pod label ${FLANNEL_LABEL_SELECTOR} only"
  else
    kubectl -n "${FLANNEL_NAMESPACE}" rollout status "daemonset/${FLANNEL_DAEMONSET}" --timeout="${FLANNEL_WAIT_TIMEOUT}"
  fi

  kubectl -n "${FLANNEL_NAMESPACE}" wait --for=condition=ready pod -l "${FLANNEL_LABEL_SELECTOR}" --timeout="${FLANNEL_WAIT_TIMEOUT}"
  log "Flannel pods are ready"
}

repo_server_needs_replace() {
  local pod_json="$1"
  python3 - "${pod_json}" <<'PY'
import json
import sys

pod = json.loads(sys.argv[1])
phase = pod.get("status", {}).get("phase", "")
if phase not in ("Running", "Succeeded"):
    print("yes")
    raise SystemExit(0)

statuses = pod.get("status", {}).get("containerStatuses") or []
if not statuses:
    print("yes")
    raise SystemExit(0)

if not all(s.get("ready") for s in statuses):
    print("yes")
    raise SystemExit(0)

print("no")
PY
}

delete_stuck_repo_server_pods() {
  log "Checking ${ARGOCD_NAMESPACE} repo-server pods"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[DRY-RUN] kubectl get pods -n ${ARGOCD_NAMESPACE} -l ${REPO_SERVER_LABEL}"
    return 0
  fi

  local pods_json
  pods_json="$(kubectl get pods -n "${ARGOCD_NAMESPACE}" -l "${REPO_SERVER_LABEL}" -o json 2>/dev/null || echo '{"items":[]}')"
  local pod_count
  pod_count="$(python3 -c "import json,sys; print(len(json.load(sys.stdin).get('items',[])))" <<<"${pods_json}")"

  if [[ "${pod_count}" -eq 0 ]]; then
    warn "No repo-server pods found (label ${REPO_SERVER_LABEL})"
    return 0
  fi

  local deleted=0
  while IFS= read -r pod_name; do
    [[ -n "${pod_name}" ]] || continue
    local pod_json
    pod_json="$(kubectl get pod -n "${ARGOCD_NAMESPACE}" "${pod_name}" -o json)"
    if [[ "$(repo_server_needs_replace "${pod_json}")" == "yes" ]]; then
      warn "Deleting stuck pod ${ARGOCD_NAMESPACE}/${pod_name}"
      kubectl delete pod -n "${ARGOCD_NAMESPACE}" "${pod_name}" --wait=true --timeout=120s
      ((deleted++)) || true
    else
      log "Pod ${pod_name} is healthy"
    fi
  done < <(python3 -c "import json,sys; d=json.load(sys.stdin); print('\n'.join(i['metadata']['name'] for i in d.get('items',[])))" <<<"${pods_json}")

  if [[ "${deleted}" -eq 0 ]]; then
    log "All repo-server pods look healthy"
  else
    log "Deleted ${deleted} repo-server pod(s)"
  fi
}

wait_for_repo_server() {
  log "Waiting for repo-server rollout"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[DRY-RUN] kubectl -n ${ARGOCD_NAMESPACE} rollout status deployment/argocd-repo-server --timeout=${REPO_SERVER_ROLLOUT_TIMEOUT}"
    return 0
  fi

  kubectl -n "${ARGOCD_NAMESPACE}" rollout status deployment/argocd-repo-server --timeout="${REPO_SERVER_ROLLOUT_TIMEOUT}"

  local ready
  ready="$(kubectl get endpoints -n "${ARGOCD_NAMESPACE}" argocd-repo-server -o jsonpath='{.subsets[0].addresses}' 2>/dev/null || true)"
  if [[ -z "${ready}" ]]; then
    die "argocd-repo-server has no ready endpoints after rollout"
  fi
  log "argocd-repo-server endpoints are ready"
}

refresh_applications() {
  if [[ "${REFRESH_APPS}" -eq 0 ]]; then
    log "Skipping Application refresh (--no-refresh)"
    return 0
  fi

  log "Hard-refreshing Argo CD Applications in ${ARGOCD_NAMESPACE}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[DRY-RUN] kubectl annotate application -n ${ARGOCD_NAMESPACE} --all argocd.argoproj.io/refresh=hard --overwrite"
    return 0
  fi

  local apps
  apps="$(kubectl get applications -n "${ARGOCD_NAMESPACE}" -o jsonpath='{.items[*].metadata.name}')"
  if [[ -z "${apps}" ]]; then
    warn "No Applications found in ${ARGOCD_NAMESPACE}"
    return 0
  fi

  local count=0
  for app in ${apps}; do
    kubectl annotate application -n "${ARGOCD_NAMESPACE}" "${app}" \
      argocd.argoproj.io/refresh=hard --overwrite >/dev/null
    ((count++)) || true
  done
  log "Annotated ${count} application(s) for hard refresh"
}

print_summary() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "Dry-run complete"
    return 0
  fi

  log "Application health summary:"
  kubectl get applications -n "${ARGOCD_NAMESPACE}" \
    -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' \
    | awk 'NR==1 || $3!="Healthy"'
}

main() {
  parse_args "$@"
  require_command kubectl
  require_command python3

  export KUBECONFIG="$(pick_kubeconfig)"
  log "Using kubeconfig: ${KUBECONFIG}"

  wait_for_cluster_api
  wait_for_flannel
  delete_stuck_repo_server_pods
  wait_for_repo_server
  refresh_applications
  print_summary

  log "Done"
}

main "$@"
