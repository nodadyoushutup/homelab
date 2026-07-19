#!/usr/bin/env bash
# Bespoke Nginx Proxy Manager config (NPM API) deploy (intentional during the AGENTS.md audit campaign).
# Bespoke self-contained entrypoint (shared *_pipeline.sh wrappers removed).
# Slice tfvars plus the NPM provider credentials (config-id
# terraform/providers/nginx_proxy_manager); no other shared swarm/dns/nfs var-files.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# pipeline -> nginx_proxy_manager -> swarm -> components -> terraform -> repo root
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform/components/swarm/nginx_proxy_manager/config"
APP_TERRAFORM_DIR="${ROOT_DIR}/terraform/components/swarm/nginx_proxy_manager/app"

CONFIG_DIR="${CONFIG_DIR:-${ROOT_DIR}/.config}"
export CONFIG_DIR

# shellcheck source=../../../scripts/terraform/resolve_config_by_id.sh
source "${ROOT_DIR}/scripts/terraform/resolve_config_by_id.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/terraform/terraform_backend_init.sh"
# shellcheck source=../../../scripts/terraform/nginx_proxy_manager_tfvars_env.sh
source "${ROOT_DIR}/scripts/terraform/nginx_proxy_manager_tfvars_env.sh"

SLICE_CONFIG_ID="$(homelab_config_id_from_terraform_dir "${ROOT_DIR}" "${TERRAFORM_DIR}")"
DEFAULT_CONFIG_TFVARS="$(homelab_resolve_config_path "${CONFIG_DIR}" "${SLICE_CONFIG_ID}")"
DEFAULT_BACKEND="$(homelab_resolve_config_path "${CONFIG_DIR}" "terraform/minio.backend")"

CONFIG_TFVARS="${NPM_CONFIG_TFVARS:-${DEFAULT_CONFIG_TFVARS}}"
BACKEND_CONFIG="${NPM_CONFIG_BACKEND:-${DEFAULT_BACKEND}}"

usage() {
  cat <<USAGE
Usage: terraform/components/swarm/nginx_proxy_manager/pipeline/config.sh [options] [config_tfvars] [backend_config]

Apply Nginx Proxy Manager certificates and proxy hosts via the NPM API (terraform init, plan, apply).

Options:
  --tfvars <path>           Config slice settings (default: ${DEFAULT_CONFIG_TFVARS})
  --backend <path>          S3 backend config (default: ${DEFAULT_BACKEND})
  -h, --help                Show this help

Environment overrides: NPM_CONFIG_TFVARS, NPM_CONFIG_BACKEND, CONFIG_DIR (default: <repo>/.config)
USAGE
}

require_file() {
  local label="$1"
  local path="$2"
  if [[ -z "${path}" || ! -f "${path}" ]]; then
    echo "[ERR] Missing ${label}: ${path}" >&2
    exit 1
  fi
}

require_terraform() {
  if ! command -v terraform >/dev/null 2>&1; then
    echo "[ERR] terraform not found on PATH" >&2
    exit 1
  fi
}

ensure_app_state_exists() {
  echo "[INFO] Verifying app remote state exists before running config stage"
  if ! homelab_terraform_init "${APP_TERRAFORM_DIR}"; then
    echo "[ERR] Unable to initialize app Terraform state. Run the app stage before config." >&2
    exit 1
  fi

  if ! (cd "${APP_TERRAFORM_DIR}" && terraform state pull >/dev/null); then
    echo "[ERR] Failed to pull app state; ensure the app stage has been applied successfully." >&2
    exit 1
  fi
}

ARGS=("$@")
while [[ ${#ARGS[@]} -gt 0 ]]; do
  case "${ARGS[0]}" in
    --tfvars)
      [[ ${#ARGS[@]} -ge 2 ]] || {
        echo "[ERR] --tfvars requires a path" >&2
        exit 2
      }
      CONFIG_TFVARS="${ARGS[1]}"
      ARGS=("${ARGS[@]:2}")
      ;;
    --backend)
      [[ ${#ARGS[@]} -ge 2 ]] || {
        echo "[ERR] --backend requires a path" >&2
        exit 2
      }
      BACKEND_CONFIG="${ARGS[1]}"
      ARGS=("${ARGS[@]:2}")
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      if [[ "${ARGS[0]}" == --* ]]; then
        echo "[ERR] Unknown option: ${ARGS[0]}" >&2
        usage >&2
        exit 2
      fi
      if [[ -z "${POSITIONAL_CONFIG_TFVARS:-}" ]]; then
        POSITIONAL_CONFIG_TFVARS="${ARGS[0]}"
      elif [[ -z "${POSITIONAL_BACKEND:-}" ]]; then
        POSITIONAL_BACKEND="${ARGS[0]}"
      else
        echo "[ERR] Unexpected argument: ${ARGS[0]}" >&2
        usage >&2
        exit 2
      fi
      ARGS=("${ARGS[@]:1}")
      ;;
  esac
done

if [[ -n "${POSITIONAL_CONFIG_TFVARS:-}" ]]; then
  CONFIG_TFVARS="${POSITIONAL_CONFIG_TFVARS}"
fi
if [[ -n "${POSITIONAL_BACKEND:-}" ]]; then
  BACKEND_CONFIG="${POSITIONAL_BACKEND}"
fi

if [[ -n "${TFVARS_FILE:-}" ]]; then
  CONFIG_TFVARS="${TFVARS_FILE}"
fi
if [[ -n "${BACKEND_FILE:-}" ]]; then
  BACKEND_CONFIG="${BACKEND_FILE}"
fi

require_terraform
require_file "config tfvars" "${CONFIG_TFVARS}"
require_file "nginx proxy manager credentials tfvars" "${NGINX_PROXY_MANAGER_TFVARS}"

echo "Terraform dir:     ${TERRAFORM_DIR}"
echo "Config tfvars:     ${CONFIG_TFVARS}"
echo "NPM creds:         ${NGINX_PROXY_MANAGER_TFVARS}"
echo "Backend config:    ${BACKEND_CONFIG}"

ensure_app_state_exists

cd "${TERRAFORM_DIR}"

echo "[STEP] terraform init (Nginx Proxy Manager config)"
if ! homelab_terraform_init "${TERRAFORM_DIR}"; then
  echo "[ERR] terraform init failed" >&2
  exit 1
fi

PLAN_ARGS=(
  -input=false
  -var-file "${CONFIG_TFVARS}"
  -var-file "${NGINX_PROXY_MANAGER_TFVARS}"
)

echo "[STEP] terraform plan (Nginx Proxy Manager config)"
if ! terraform plan "${PLAN_ARGS[@]}"; then
  echo "[ERR] terraform plan failed" >&2
  exit 1
fi

echo "[STEP] terraform apply (Nginx Proxy Manager config)"
if ! terraform apply -input=false -auto-approve -parallelism=1 "${PLAN_ARGS[@]}"; then
  echo "[ERR] terraform apply failed" >&2
  exit 1
fi

echo "[DONE] Nginx Proxy Manager config apply complete."
