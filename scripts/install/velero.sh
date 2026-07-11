#!/usr/bin/env bash
# Install or upgrade Velero (Helm) and apply homelab manifests (BSLs, schedules, ESO).
# Creates per-app MinIO buckets on VELERO_MINIO_URL using MINIO_ROOT_* from .config/docker/minio.env.
#
# Prerequisites: kubectl, cluster access, snapshot-controller + CSI VolumeSnapshotClasses,
# velero-s3-credentials in namespace velero (Vault ESO or bootstrap secret).
#
# Usage:
#   scripts/install/velero.sh
#   VELERO_SKIP_BUCKETS=1 scripts/install/velero.sh
#   VELERO_SKIP_HELM=1 scripts/install/velero.sh   # manifests + buckets only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
# shellcheck source=../terraform/load_root_env.sh
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

VELERO_NAMESPACE="${VELERO_NAMESPACE:-velero}"
VELERO_CHART_VERSION="${VELERO_CHART_VERSION:-12.0.1}"
VELERO_HELM_REPO="${VELERO_HELM_REPO:-https://vmware-tanzu.github.io/helm-charts}"
VELERO_MINIO_URL="${VELERO_MINIO_URL:-http://192.168.1.25:9000}"
VELERO_SKIP_BUCKETS="${VELERO_SKIP_BUCKETS:-0}"
VELERO_SKIP_HELM="${VELERO_SKIP_HELM:-0}"
VELERO_SKIP_MANIFESTS="${VELERO_SKIP_MANIFESTS:-0}"

VELERO_VALUES="${ROOT_DIR}/kubernetes/velero/values.yaml"
VELERO_MANIFESTS_DIR="${ROOT_DIR}/kubernetes/velero/manifests"
BSL_FILE="${VELERO_MANIFESTS_DIR}/backupstoragelocations-apps.yaml"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[ERR] Missing required command: $1" >&2
    exit 1
  fi
}

helm_upgrade_velero() {
  local helm_args=(
    upgrade --install velero vmware-tanzu/velero
    --version "${VELERO_CHART_VERSION}"
    --namespace "${VELERO_NAMESPACE}"
    --create-namespace
    --wait --timeout 10m
  )

  if command -v helm >/dev/null 2>&1; then
    helm repo add vmware-tanzu "${VELERO_HELM_REPO}" >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1 || true
    helm "${helm_args[@]}" -f "${VELERO_VALUES}"
    return
  fi
  if command -v docker >/dev/null 2>&1; then
    docker run --rm \
      -v "${VELERO_VALUES}:/values.yaml:ro" \
      -v "${HOME}/.kube:/root/.kube:ro" \
      -e KUBECONFIG=/root/.kube/config \
      --network host \
      --entrypoint sh \
      alpine/helm:3.16.4 \
      -c "helm repo add vmware-tanzu '${VELERO_HELM_REPO}' >/dev/null 2>&1; helm repo update >/dev/null 2>&1; helm upgrade --install velero vmware-tanzu/velero --version '${VELERO_CHART_VERSION}' --namespace '${VELERO_NAMESPACE}' --create-namespace -f /values.yaml --wait --timeout 10m"
    return
  fi
  echo "[ERR] Need helm or docker to run Helm." >&2
  exit 1
}

minio_buckets_from_bsl() {
  grep -E '^  name:' "${BSL_FILE}" | awk '{print $2}' | sort -u
}

create_minio_buckets() {
  if [[ "${VELERO_SKIP_BUCKETS}" == "1" ]]; then
    echo "[INFO] Skipping MinIO bucket creation (VELERO_SKIP_BUCKETS=1)."
    return
  fi

  if [[ -z "${MINIO_ROOT_USER:-}" || -z "${MINIO_ROOT_PASSWORD:-}" ]]; then
    echo "[ERR] MINIO_ROOT_USER and MINIO_ROOT_PASSWORD must be set (e.g. in ${ROOT_DIR}/.config/docker/minio.env)." >&2
    exit 1
  fi

  local buckets
  buckets="$(minio_buckets_from_bsl)"
  buckets="$(printf '%s\nvelero-misc\n' "${buckets}")"

  echo "[INFO] Creating MinIO buckets on ${VELERO_MINIO_URL} ..."

  if command -v docker >/dev/null 2>&1; then
    local bucket_list
    bucket_list="$(echo "${buckets}" | tr '\n' ' ')"
    docker run --rm --network host \
      -e MINIO_ROOT_USER -e MINIO_ROOT_PASSWORD \
      -e VELERO_MINIO_URL="${VELERO_MINIO_URL}" \
      --entrypoint /bin/sh \
      minio/mc:latest \
      -c "
        set -e
        mc alias set v \"\${VELERO_MINIO_URL}\" \"\${MINIO_ROOT_USER}\" \"\${MINIO_ROOT_PASSWORD}\"
        for b in ${bucket_list}; do
          mc mb --ignore-existing \"v/\${b}\"
        done
        echo '[INFO] Buckets:'
        mc ls v/
      "
  elif command -v mc >/dev/null 2>&1; then
    mc alias set v "${VELERO_MINIO_URL}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"
    while IFS= read -r b; do
      [[ -z "${b}" ]] && continue
      mc mb --ignore-existing "v/${b}"
    done <<<"${buckets}"
    mc ls v/
  else
    echo "[ERR] Need docker or mc to create MinIO buckets." >&2
    exit 1
  fi
}

check_prerequisites() {
  require_command kubectl

  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "[ERR] kubectl cannot reach the cluster." >&2
    exit 1
  fi

  if kubectl get volumesnapshotclass truenas-iscsi-snapclass >/dev/null 2>&1; then
    echo "[INFO] VolumeSnapshotClass truenas-iscsi-snapclass found."
  else
    echo "[WARN] VolumeSnapshotClass truenas-iscsi-snapclass not found. Install snapshot-controller first." >&2
  fi
}

apply_manifests() {
  if [[ "${VELERO_SKIP_MANIFESTS}" == "1" ]]; then
    echo "[INFO] Skipping manifest apply (VELERO_SKIP_MANIFESTS=1)."
    return
  fi

  echo "[INFO] Applying Velero manifests from ${VELERO_MANIFESTS_DIR} ..."
  kubectl apply -f "${VELERO_MANIFESTS_DIR}/namespace.yaml"
  kubectl apply --server-side --force-conflicts -f "${VELERO_MANIFESTS_DIR}/backupstoragelocations-apps.yaml"
  kubectl apply -f "${VELERO_MANIFESTS_DIR}/secretstore.yaml" \
    -f "${VELERO_MANIFESTS_DIR}/vault-reader-secret.yaml" \
    -f "${VELERO_MANIFESTS_DIR}/externalsecret-s3.yaml" \
    -f "${VELERO_MANIFESTS_DIR}/ingress.yaml" 2>/dev/null || true
  kubectl apply -f "${VELERO_MANIFESTS_DIR}"/schedule-*.yaml

  if kubectl -n "${VELERO_NAMESPACE}" get secret velero-s3-credentials >/dev/null 2>&1; then
    echo "[INFO] Secret velero-s3-credentials present."
  else
    echo "[WARN] Secret velero-s3-credentials missing. Bootstrap or wait for ExternalSecret." >&2
    echo "       See kubernetes/velero/secret-velero-s3-credentials.example.yaml" >&2
  fi
}

install_helm() {
  if [[ "${VELERO_SKIP_HELM}" == "1" ]]; then
    echo "[INFO] Skipping Helm (VELERO_SKIP_HELM=1)."
    return
  fi

  if [[ ! -f "${VELERO_VALUES}" ]]; then
    echo "[ERR] Missing ${VELERO_VALUES}" >&2
    exit 1
  fi

  echo "[INFO] Helm upgrade velero chart ${VELERO_CHART_VERSION} ..."
  helm_upgrade_velero

  echo "[INFO] Waiting for node-agent daemonset ..."
  kubectl -n "${VELERO_NAMESPACE}" rollout status daemonset/node-agent --timeout=5m
  kubectl -n "${VELERO_NAMESPACE}" rollout status deployment/velero --timeout=5m
}

main() {
  check_prerequisites
  create_minio_buckets
  install_helm
  apply_manifests

  echo ""
  echo "[OK] Velero install/upgrade finished."
  echo "     Namespace: ${VELERO_NAMESPACE}"
  echo "     MinIO:     ${VELERO_MINIO_URL}"
  echo "     Restore:   scripts/misc/velero_restore.sh <backup-name>"
  echo ""
  kubectl get pods -n "${VELERO_NAMESPACE}"
  kubectl get backupstoragelocation -n "${VELERO_NAMESPACE}" 2>/dev/null | head -10 || true
}

main "$@"
