#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/pipeline"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="mcp-argocd"
STAGE_NAME="MCP ArgoCD app"
ENTRYPOINT_RELATIVE="terraform/docker/mcp-argocd/app/pipeline/app.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/docker/mcp-argocd/app"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${TFVARS_DIR:-/mnt/eapp/.tfvars}}"
DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE:-${TFVARS_HOME_DIR}/mcp-argocd/app.tfvars}"
DEFAULT_BACKEND_FILE="${DEFAULT_BACKEND_FILE:-${TFVARS_HOME_DIR}/minio.backend.hcl}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

PIPELINE_ARGS=("$@")

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[ERR] Missing required command: $1" >&2
    exit 1
  }
}

tfvars_token_needs_bootstrap() {
  local tfvars_file="$1"
  local token_line=""

  token_line="$(grep -nE '^[[:space:]]*argocd_api_token[[:space:]]*=' "${tfvars_file}" | head -n 1 || true)"

  if [[ -z "${token_line}" ]]; then
    return 0
  fi

  if [[ "${token_line}" =~ REPLACE_ME ]]; then
    return 0
  fi

  if [[ "${token_line}" =~ ^[0-9]+:[[:space:]]*argocd_api_token[[:space:]]*=[[:space:]]*\"\"[[:space:]]*$ ]]; then
    return 0
  fi

  return 1
}

ensure_admin_apikey_capability() {
  local admin_caps=""

  if ! kubectl -n argocd get configmap argocd-cm >/dev/null 2>&1; then
    echo "[ERR] argocd/argocd-cm not found. Deploy Argo CD first." >&2
    exit 1
  fi

  admin_caps="$(kubectl -n argocd get configmap argocd-cm -o jsonpath='{.data.accounts\.admin}' 2>/dev/null || true)"
  if [[ "${admin_caps}" == *apiKey* ]]; then
    return 0
  fi

  echo "[STEP] Enabling Argo CD admin apiKey capability"
  kubectl -n argocd patch configmap argocd-cm \
    --type merge \
    -p '{"data":{"accounts.admin":"apiKey, login","admin.enabled":"true"}}'
  kubectl -n argocd rollout restart deployment/argocd-server
  kubectl -n argocd rollout status deployment/argocd-server --timeout=5m
}

build_argocd_core_kubeconfig() {
  local kubeconfig_file=""
  local kube_context=""

  kubeconfig_file="$(mktemp)"
  kubectl config view --minify --raw > "${kubeconfig_file}"
  kube_context="$(kubectl --kubeconfig "${kubeconfig_file}" config current-context)"
  kubectl --kubeconfig "${kubeconfig_file}" config set-context "${kube_context}" --namespace=argocd >/dev/null
  echo "${kubeconfig_file}"
}

bootstrap_argocd_token_for_pipeline() {
  local tfvars_file="$1"
  local token_id="${ARGOCD_MCP_TOKEN_ID:-mcp-argocd-swarm}"
  local token_ttl="${ARGOCD_MCP_TOKEN_EXPIRES_IN:-0s}"
  local core_kubeconfig=""
  local existing_token_count=""
  local generated_token=""

  if ! tfvars_token_needs_bootstrap "${tfvars_file}"; then
    return 0
  fi

  require_cmd kubectl
  require_cmd argocd
  require_cmd python3

  ensure_admin_apikey_capability

  core_kubeconfig="$(build_argocd_core_kubeconfig)"
  existing_token_count="$(KUBECONFIG="${core_kubeconfig}" argocd account get --account admin --core -o json \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d.get("tokens", [])))')"

  if [[ "${existing_token_count}" -gt 0 ]]; then
    echo "[INFO] admin already has ${existing_token_count} token(s); issuing managed token id ${token_id} for this pipeline."
  else
    echo "[STEP] admin has no API tokens; issuing managed token id ${token_id}."
  fi

  KUBECONFIG="${core_kubeconfig}" argocd account delete-token --account admin --core --id "${token_id}" >/dev/null 2>&1 || true
  generated_token="$(KUBECONFIG="${core_kubeconfig}" argocd account generate-token --account admin --core --id "${token_id}" --expires-in "${token_ttl}" | tr -d '\r\n')"
  rm -f "${core_kubeconfig}"

  if [[ -z "${generated_token}" ]]; then
    echo "[ERR] Failed to generate Argo CD API token." >&2
    exit 1
  fi

  PLAN_ARGS_EXTRA+=("-var" "argocd_api_token=${generated_token}")
  APPLY_ARGS_EXTRA+=("-var" "argocd_api_token=${generated_token}")
  echo "[INFO] Injected generated argocd_api_token for terraform plan/apply."
}

pipeline_pre_terraform() {
  bootstrap_argocd_token_for_pipeline "${TFVARS_PATH}"
}

source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
