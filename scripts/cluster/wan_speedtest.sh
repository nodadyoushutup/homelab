#!/usr/bin/env bash
# Run Ookla speed tests from Proxmox and a Kubernetes pod, then print download/upload summary.
#
# Usage:
#   ./scripts/cluster/wan_speedtest.sh
#
#   SSHPASS=other-password ./scripts/cluster/wan_speedtest.sh   # override default
#
#   PROXMOX_HOST=192.168.1.10 KUBE_NODE=k8s-wk-10 ./scripts/cluster/wan_speedtest.sh
#
# Options:
#   --proxmox-only    Skip the Kubernetes pod test
#   --kube-only       Skip the Proxmox test
#   --runs N          Speed test iterations per target (default: 1)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROXMOX_HOST="${PROXMOX_HOST:-192.168.1.10}"
PROXMOX_USER="${PROXMOX_USER:-root}"
PROXMOX_SSH="${PROXMOX_SSH:-${PROXMOX_USER}@${PROXMOX_HOST}}"
SSHPASS="${SSHPASS:-S#nvhs89vher}"

KUBE_NODE="${KUBE_NODE:-k8s-wk-10}"
KUBE_NAMESPACE="${KUBE_NAMESPACE:-clusterplex}"
KUBE_POD_NAME="${KUBE_POD_NAME:-wan-speedtest-tmp}"

RUNS=1
DO_PROXMOX=1
DO_KUBE=1

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERR] $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Run speedtest-cli on Proxmox (${PROXMOX_SSH}) and a temporary pod on node ${KUBE_NODE}.

Environment:
  SSHPASS          Proxmox SSH password (default: homelab root password)
  PROXMOX_HOST     Proxmox host (default: 192.168.1.10)
  PROXMOX_USER     SSH user (default: root)
  KUBE_NODE        Kubernetes node for pod test (default: k8s-wk-10)
  KUBE_NAMESPACE   Namespace for temp pod (default: clusterplex)

Options:
  --proxmox-only   Test Proxmox only
  --kube-only      Test Kubernetes pod only
  --runs N         Iterations per target (default: 1)
  -h, --help       Show this help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --proxmox-only) DO_KUBE=0 ;;
    --kube-only)    DO_PROXMOX=0 ;;
    --runs)
      shift
      RUNS="${1:?--runs requires a number}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1 (try --help)"
      ;;
  esac
  shift
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

parse_speedtest_simple() {
  local output="$1"
  local ping download upload
  ping="$(sed -n 's/^Ping: \(.*\)$/\1/p' <<<"$output" | head -1)"
  download="$(sed -n 's/^Download: \(.*\)$/\1/p' <<<"$output" | head -1)"
  upload="$(sed -n 's/^Upload: \(.*\)$/\1/p' <<<"$output" | head -1)"
  if [ -z "$download" ] || [ -z "$upload" ]; then
    warn "Failed to parse speedtest output:"
    echo "$output" >&2
    return 1
  fi
  printf '%s\t%s\t%s\n' "${ping:-n/a}" "$download" "$upload"
}

print_results_header() {
  printf '\n%-12s %-6s %-14s %-14s %-14s\n' "TARGET" "RUN" "DOWNLOAD" "UPLOAD" "PING"
  printf '%-12s %-6s %-14s %-14s %-14s\n' "--------" "---" "--------" "------" "----"
}

print_result_row() {
  local target="$1"
  local run="$2"
  local download="$3"
  local upload="$4"
  local ping="$5"
  printf '%-12s %-6s %-14s %-14s %-14s\n' "$target" "$run" "$download" "$upload" "$ping"
}

proxmox_ssh() {
  local remote_cmd="$1"
  if [ -n "${SSHPASS:-}" ]; then
    require_cmd sshpass
    SSHPASS="$SSHPASS" sshpass -e ssh \
      -o StrictHostKeyChecking=no \
      -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no \
      "$PROXMOX_SSH" "$remote_cmd"
  else
    ssh -o StrictHostKeyChecking=no "$PROXMOX_SSH" "$remote_cmd"
  fi
}

ensure_proxmox_speedtest() {
  proxmox_ssh 'command -v speedtest-cli >/dev/null 2>&1 || {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq speedtest-cli >/dev/null 2>&1
  }'
}

run_proxmox_speedtests() {
  local run output parsed ping download upload public_ip
  log "Proxmox: ${PROXMOX_SSH}"
  ensure_proxmox_speedtest
  public_ip="$(proxmox_ssh 'curl -s --max-time 10 ifconfig.me || true')"
  [ -n "$public_ip" ] && log "Proxmox public IP: ${public_ip}"

  for run in $(seq 1 "$RUNS"); do
    log "Proxmox speed test run ${run}/${RUNS}..."
    output="$(proxmox_ssh 'speedtest-cli --secure --simple')"
    parsed="$(parse_speedtest_simple "$output")"
    ping="$(cut -f1 <<<"$parsed")"
    download="$(cut -f2 <<<"$parsed")"
    upload="$(cut -f3 <<<"$parsed")"
    print_result_row "proxmox" "$run" "$download" "$upload" "$ping"
  done
}

KUBE_POD_CREATED=0

cleanup_kube_pod() {
  if [ "$KUBE_POD_CREATED" -eq 1 ]; then
    kubectl delete pod -n "$KUBE_NAMESPACE" "$KUBE_POD_NAME" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    KUBE_POD_CREATED=0
  fi
}

run_kube_speedtests() {
  local run output parsed ping download upload public_ip
  trap cleanup_kube_pod EXIT

  require_cmd kubectl
  log "Kubernetes: pod on node ${KUBE_NODE} (namespace ${KUBE_NAMESPACE})"

  kubectl get namespace "$KUBE_NAMESPACE" >/dev/null 2>&1 \
    || die "Namespace not found: ${KUBE_NAMESPACE}"

  kubectl delete pod -n "$KUBE_NAMESPACE" "$KUBE_POD_NAME" --ignore-not-found --wait=true >/dev/null 2>&1 || true

  kubectl run "$KUBE_POD_NAME" -n "$KUBE_NAMESPACE" --restart=Never \
    --image=alpine:3.20 \
    --overrides="$(cat <<JSON
{
  "spec": {
    "nodeSelector": {"kubernetes.io/hostname": "${KUBE_NODE}"},
    "containers": [{
      "name": "${KUBE_POD_NAME}",
      "image": "alpine:3.20",
      "command": ["sleep", "600"]
    }]
  }
}
JSON
)" 2>&1 | grep -v 'would violate PodSecurity' || true

  KUBE_POD_CREATED=1
  kubectl wait -n "$KUBE_NAMESPACE" "pod/${KUBE_POD_NAME}" --for=condition=Ready --timeout=120s >/dev/null

  kubectl exec -n "$KUBE_NAMESPACE" "$KUBE_POD_NAME" -- sh -c '
    apk add --no-cache curl python3 py3-pip >/dev/null 2>&1
    pip3 install speedtest-cli --break-system-packages -q 2>/dev/null || pip3 install speedtest-cli -q 2>/dev/null
  ' >/dev/null

  public_ip="$(kubectl exec -n "$KUBE_NAMESPACE" "$KUBE_POD_NAME" -- \
    sh -c 'curl -s --max-time 10 ifconfig.me || true')"
  [ -n "$public_ip" ] && log "Pod public IP: ${public_ip}"

  for run in $(seq 1 "$RUNS"); do
    log "Kubernetes speed test run ${run}/${RUNS}..."
    output="$(kubectl exec -n "$KUBE_NAMESPACE" "$KUBE_POD_NAME" -- speedtest-cli --secure --simple)"
    parsed="$(parse_speedtest_simple "$output")"
    ping="$(cut -f1 <<<"$parsed")"
    download="$(cut -f2 <<<"$parsed")"
    upload="$(cut -f3 <<<"$parsed")"
    print_result_row "kube-pod" "$run" "$download" "$upload" "$ping"
  done

  cleanup_kube_pod
  trap - EXIT
}

main() {
  if [ "$DO_PROXMOX" -eq 0 ] && [ "$DO_KUBE" -eq 0 ]; then
    die "Nothing to do: enable Proxmox and/or Kubernetes test"
  fi

  print_results_header

  if [ "$DO_PROXMOX" -eq 1 ]; then
    run_proxmox_speedtests
  fi

  if [ "$DO_KUBE" -eq 1 ]; then
    run_kube_speedtests
  fi

  printf '\n'
  log "Done."
}

main
