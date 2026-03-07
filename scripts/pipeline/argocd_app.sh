#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/pipeline"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

# Temporary plaintext constants (replace with secret management later).
ARGOCD_NAMESPACE="argocd"
ARGOCD_MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
ARGOCD_ADMIN_USERNAME="admin"
ARGOCD_ADMIN_PASSWORD="password"
ARGOCD_SERVER_EXPOSURE_MODE="NodePort"
ARGOCD_SERVER_HTTP_NODEPORT="30080"
ARGOCD_SERVER_HTTPS_NODEPORT="30443"

# GitOps app-of-apps settings.
ARGOCD_GITOPS_APPSET_NAME="${ARGOCD_GITOPS_APPSET_NAME:-homelab-addons}"
ARGOCD_GITOPS_REPO_URL="${ARGOCD_GITOPS_REPO_URL:-git@github.com:nodadyoushutup/homelab.git}"
ARGOCD_GITOPS_REPO_REVISION="${ARGOCD_GITOPS_REPO_REVISION:-HEAD}"
ARGOCD_GITOPS_APPS_FILE="${ARGOCD_GITOPS_APPS_FILE:-${ROOT_DIR}/kubernetes/argocd/app-of-apps.yaml}"
ARGOCD_GITOPS_REPO_SECRET_NAME="${ARGOCD_GITOPS_REPO_SECRET_NAME:-homelab-gitops-repo}"
ARGOCD_GITOPS_REPO_USERNAME="${ARGOCD_GITOPS_REPO_USERNAME:-}"
ARGOCD_GITOPS_REPO_PASSWORD="${ARGOCD_GITOPS_REPO_PASSWORD:-}"
ARGOCD_GITOPS_REPO_SSH_PRIVATE_KEY="${ARGOCD_GITOPS_REPO_SSH_PRIVATE_KEY:-}"

GITOPS_CHILD_APPS=(
  "metallb"
  "ingress-nginx"
)

wait_for_secret() {
  local ns="$1"
  local name="$2"
  local max_attempts="${3:-60}"
  local sleep_seconds="${4:-2}"
  local attempt=1

  while (( attempt <= max_attempts )); do
    if kubectl -n "${ns}" get secret "${name}" >/dev/null 2>&1; then
      return 0
    fi
    sleep "${sleep_seconds}"
    ((attempt++))
  done

  echo "[ERR] Timed out waiting for secret ${ns}/${name}" >&2
  return 1
}

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "[ERR] Missing required command: ${cmd}" >&2
    exit 1
  fi
}

retry_command() {
  local max_attempts="$1"
  local sleep_seconds="$2"
  shift 2

  local attempt=1
  until "$@"; do
    if (( attempt >= max_attempts )); then
      echo "[ERR] Command failed after ${attempt} attempt(s): $*" >&2
      return 1
    fi
    echo "[WARN] Command failed (attempt ${attempt}/${max_attempts}), retrying in ${sleep_seconds}s: $*"
    sleep "${sleep_seconds}"
    ((attempt++))
  done
}

ensure_bcrypt_available() {
  python3 - <<'PY'
import importlib.util
import sys
if importlib.util.find_spec("bcrypt") is None:
    print("[ERR] Python module 'bcrypt' is required (pip install bcrypt)", file=sys.stderr)
    sys.exit(1)
PY
}

generate_bcrypt_hash() {
  local plaintext="$1"
  python3 - "$plaintext" <<'PY'
import bcrypt
import sys
password = sys.argv[1].encode("utf-8")
print(bcrypt.hashpw(password, bcrypt.gensalt(rounds=10)).decode("utf-8"))
PY
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

pick_primary_node_ip() {
  local control_plane_ip=""
  control_plane_ip="$(kubectl get nodes -l 'node-role.kubernetes.io/control-plane' \
    -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)"
  if [[ -n "${control_plane_ip}" ]]; then
    echo "${control_plane_ip}"
    return 0
  fi

  kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'
}

configure_argocd_service_exposure() {
  case "${ARGOCD_SERVER_EXPOSURE_MODE}" in
    NodePort|nodeport)
      echo "[STEP] Exposing argocd-server as NodePort (${ARGOCD_SERVER_HTTP_NODEPORT}/${ARGOCD_SERVER_HTTPS_NODEPORT})"
      kubectl -n "${ARGOCD_NAMESPACE}" patch svc argocd-server \
        --type merge \
        -p "{\"spec\":{\"type\":\"NodePort\",\"ports\":[{\"name\":\"http\",\"port\":80,\"protocol\":\"TCP\",\"targetPort\":8080,\"nodePort\":${ARGOCD_SERVER_HTTP_NODEPORT}},{\"name\":\"https\",\"port\":443,\"protocol\":\"TCP\",\"targetPort\":8080,\"nodePort\":${ARGOCD_SERVER_HTTPS_NODEPORT}}]}}"
      ;;
    ClusterIP|clusterip)
      echo "[STEP] Keeping argocd-server as ClusterIP"
      kubectl -n "${ARGOCD_NAMESPACE}" patch svc argocd-server \
        --type merge \
        -p '{"spec":{"type":"ClusterIP"}}'
      ;;
    *)
      echo "[ERR] Unsupported ARGOCD_SERVER_EXPOSURE_MODE: ${ARGOCD_SERVER_EXPOSURE_MODE}" >&2
      exit 1
      ;;
  esac
}

wait_for_argocd_application_synced_healthy() {
  local app_name="$1"
  local max_attempts="${2:-180}"
  local sleep_seconds="${3:-5}"
  local attempt=1
  local sync_status=""
  local health_status=""
  local condition_types=""
  local stable_hits=0

  while (( attempt <= max_attempts )); do
    sync_status="$(kubectl -n "${ARGOCD_NAMESPACE}" get application "${app_name}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
    health_status="$(kubectl -n "${ARGOCD_NAMESPACE}" get application "${app_name}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
    condition_types="$(kubectl -n "${ARGOCD_NAMESPACE}" get application "${app_name}" -o jsonpath='{range .status.conditions[*]}{.type}{" "}{end}' 2>/dev/null || true)"

    if [[ " ${condition_types} " == *" ComparisonError "* ]] || [[ " ${condition_types} " == *" InvalidSpecError "* ]] || [[ " ${condition_types} " == *" ReconciliationError "* ]]; then
      echo "[ERR] Application ${app_name} has Argo CD error condition(s): ${condition_types}" >&2
      kubectl -n "${ARGOCD_NAMESPACE}" get application "${app_name}" -o yaml >&2 || true
      return 1
    fi

    if [[ "${sync_status}" == "Synced" && "${health_status}" == "Healthy" ]]; then
      ((stable_hits++))
      if (( stable_hits >= 3 )); then
        echo "[INFO] Argo CD application ${app_name} is Synced/Healthy"
        return 0
      fi
    else
      stable_hits=0
    fi

    sleep "${sleep_seconds}"
    ((attempt++))
  done

  echo "[ERR] Application ${app_name} did not become Synced/Healthy" >&2
  kubectl -n "${ARGOCD_NAMESPACE}" get application "${app_name}" -o yaml >&2 || true
  return 1
}

wait_for_argocd_application_present() {
  local app_name="$1"
  local max_attempts="${2:-120}"
  local sleep_seconds="${3:-2}"
  local attempt=1

  while (( attempt <= max_attempts )); do
    if kubectl -n "${ARGOCD_NAMESPACE}" get application "${app_name}" >/dev/null 2>&1; then
      return 0
    fi
    sleep "${sleep_seconds}"
    ((attempt++))
  done

  echo "[ERR] Timed out waiting for Argo CD application ${app_name}" >&2
  return 1
}

wait_for_argocd_applicationset_present() {
  local appset_name="$1"
  local max_attempts="${2:-120}"
  local sleep_seconds="${3:-2}"
  local attempt=1

  while (( attempt <= max_attempts )); do
    if kubectl -n "${ARGOCD_NAMESPACE}" get applicationset "${appset_name}" >/dev/null 2>&1; then
      return 0
    fi
    sleep "${sleep_seconds}"
    ((attempt++))
  done

  echo "[ERR] Timed out waiting for Argo CD ApplicationSet ${appset_name}" >&2
  return 1
}

auto_load_gitops_ssh_key_if_available() {
  if [[ -n "${ARGOCD_GITOPS_REPO_SSH_PRIVATE_KEY}" ]]; then
    return 0
  fi

  if [[ "${ARGOCD_GITOPS_REPO_URL}" != git@* && "${ARGOCD_GITOPS_REPO_URL}" != ssh://* ]]; then
    return 0
  fi

  local default_key="${HOME}/.ssh/id_ed25519"
  if [[ -f "${default_key}" ]]; then
    ARGOCD_GITOPS_REPO_SSH_PRIVATE_KEY="$(cat "${default_key}")"
    echo "[INFO] Loaded SSH key from ${default_key} for Argo CD repo access"
  fi
}

configure_gitops_repo_secret_if_needed() {
  if [[ -n "${ARGOCD_GITOPS_REPO_SSH_PRIVATE_KEY}" ]]; then
    echo "[STEP] Configuring Argo CD repository secret (SSH key auth)"
    kubectl -n "${ARGOCD_NAMESPACE}" apply -f - <<EOF_SSH
apiVersion: v1
kind: Secret
metadata:
  name: ${ARGOCD_GITOPS_REPO_SECRET_NAME}
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: ${ARGOCD_GITOPS_REPO_URL}
  sshPrivateKey: |
$(printf '%s\n' "${ARGOCD_GITOPS_REPO_SSH_PRIVATE_KEY}" | sed 's/^/    /')
EOF_SSH
    return 0
  fi

  if [[ -n "${ARGOCD_GITOPS_REPO_USERNAME}" && -n "${ARGOCD_GITOPS_REPO_PASSWORD}" ]]; then
    echo "[STEP] Configuring Argo CD repository secret (HTTPS auth)"
    kubectl -n "${ARGOCD_NAMESPACE}" apply -f - <<EOF_HTTPS
apiVersion: v1
kind: Secret
metadata:
  name: ${ARGOCD_GITOPS_REPO_SECRET_NAME}
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: ${ARGOCD_GITOPS_REPO_URL}
  username: ${ARGOCD_GITOPS_REPO_USERNAME}
  password: ${ARGOCD_GITOPS_REPO_PASSWORD}
EOF_HTTPS
    return 0
  fi

  echo "[INFO] No git credentials configured; assuming repo is publicly readable or already configured in Argo CD"
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[&|]/\\&/g'
}

cleanup_legacy_gitops_objects() {
  local legacy_apps=(
    "homelab-root"
    "metallb-namespace"
    "metallb-config"
    "ingress-nginx-namespace"
  )

  if kubectl -n "${ARGOCD_NAMESPACE}" get applicationset networking-core >/dev/null 2>&1; then
    echo "[STEP] Removing legacy ApplicationSet/networking-core"
    kubectl -n "${ARGOCD_NAMESPACE}" delete applicationset networking-core --ignore-not-found=true
  fi

  for app in "${legacy_apps[@]}"; do
    if kubectl -n "${ARGOCD_NAMESPACE}" get application "${app}" >/dev/null 2>&1; then
      echo "[STEP] Removing legacy Application/${app}"
      kubectl -n "${ARGOCD_NAMESPACE}" delete application "${app}" --ignore-not-found=true
    fi
  done
}

apply_app_of_apps_manifest() {
  if [[ ! -f "${ARGOCD_GITOPS_APPS_FILE}" ]]; then
    echo "[ERR] Missing app-of-apps manifest: ${ARGOCD_GITOPS_APPS_FILE}" >&2
    exit 1
  fi

  local rendered_file=""
  rendered_file="$(mktemp)"
  sed \
    -e "s|__ARGOCD_GITOPS_REPO_URL__|$(escape_sed_replacement "${ARGOCD_GITOPS_REPO_URL}")|g" \
    -e "s|__ARGOCD_GITOPS_REPO_REVISION__|$(escape_sed_replacement "${ARGOCD_GITOPS_REPO_REVISION}")|g" \
    "${ARGOCD_GITOPS_APPS_FILE}" > "${rendered_file}"

  echo "[STEP] Applying app-of-apps manifest (${ARGOCD_GITOPS_APPS_FILE})"
  kubectl -n "${ARGOCD_NAMESPACE}" apply -f "${rendered_file}"
  rm -f "${rendered_file}"
}

main() {
  require_command kubectl
  require_command python3
  ensure_bcrypt_available

  export KUBECONFIG="$(pick_kubeconfig)"

  echo "[INFO] Using kubeconfig: ${KUBECONFIG}"
  kubectl cluster-info >/dev/null

  echo "[STEP] Creating namespace (${ARGOCD_NAMESPACE})"
  kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

  echo "[STEP] Installing/updating Argo CD manifests"
  retry_command 5 5 \
    kubectl apply --server-side --force-conflicts -n "${ARGOCD_NAMESPACE}" -f "${ARGOCD_MANIFEST_URL}"

  configure_argocd_service_exposure

  echo "[STEP] Waiting for Argo CD workloads"
  kubectl -n "${ARGOCD_NAMESPACE}" rollout status statefulset/argocd-application-controller --timeout=10m
  kubectl -n "${ARGOCD_NAMESPACE}" rollout status deployment/argocd-server --timeout=10m
  kubectl -n "${ARGOCD_NAMESPACE}" rollout status deployment/argocd-repo-server --timeout=10m
  kubectl -n "${ARGOCD_NAMESPACE}" rollout status deployment/argocd-redis --timeout=10m
  kubectl -n "${ARGOCD_NAMESPACE}" rollout status deployment/argocd-applicationset-controller --timeout=10m

  echo "[STEP] Ensuring admin account is enabled"
  kubectl -n "${ARGOCD_NAMESPACE}" patch configmap argocd-cm \
    --type merge \
    -p '{"data":{"admin.enabled":"true"}}'

  echo "[STEP] Waiting for argocd-secret"
  wait_for_secret "${ARGOCD_NAMESPACE}" "argocd-secret" 120 2

  echo "[STEP] Setting fixed Argo CD admin password"
  local password_hash=""
  local password_mtime=""
  password_hash="$(generate_bcrypt_hash "${ARGOCD_ADMIN_PASSWORD}")"
  password_mtime="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  kubectl -n "${ARGOCD_NAMESPACE}" patch secret argocd-secret \
    --type merge \
    -p "{\"stringData\":{\"admin.password\":\"${password_hash}\",\"admin.passwordMtime\":\"${password_mtime}\"}}"

  echo "[STEP] Restarting Argo CD server to pick up credentials"
  kubectl -n "${ARGOCD_NAMESPACE}" rollout restart deployment/argocd-server
  kubectl -n "${ARGOCD_NAMESPACE}" rollout status deployment/argocd-server --timeout=5m

  auto_load_gitops_ssh_key_if_available
  configure_gitops_repo_secret_if_needed
  cleanup_legacy_gitops_objects
  apply_app_of_apps_manifest

  wait_for_argocd_applicationset_present "${ARGOCD_GITOPS_APPSET_NAME}" 120 2

  local app
  for app in "${GITOPS_CHILD_APPS[@]}"; do
    wait_for_argocd_application_present "${app}" 180 2
  done

  for app in "${GITOPS_CHILD_APPS[@]}"; do
    wait_for_argocd_application_synced_healthy "${app}" 240 5
  done

  local access_ip=""
  access_ip="$(pick_primary_node_ip)"

  cat <<EOF_DONE
[DONE] Argo CD is installed and app-of-apps is configured.
Admin username: ${ARGOCD_ADMIN_USERNAME}
Admin password: ${ARGOCD_ADMIN_PASSWORD}
Namespace: ${ARGOCD_NAMESPACE}
LAN URL: https://${access_ip}:${ARGOCD_SERVER_HTTPS_NODEPORT}
ApplicationSet: ${ARGOCD_GITOPS_APPSET_NAME}
GitOps repo: ${ARGOCD_GITOPS_REPO_URL}
GitOps revision: ${ARGOCD_GITOPS_REPO_REVISION}
GitOps app-of-apps file: ${ARGOCD_GITOPS_APPS_FILE}

Argo CD child apps now reconcile from git commits:
- metallb
- ingress-nginx
EOF_DONE
}

main "$@"
