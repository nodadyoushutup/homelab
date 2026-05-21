#!/usr/bin/env bash
# Bespoke Nginx Proxy Manager config (NPM API) deploy — no shared swarm_pipeline.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/nginx_proxy_manager/config"
APP_TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/nginx_proxy_manager/app"

SITE_ENV="${ROOT_DIR}/.config/docker/site.env"
if [[ -f "${SITE_ENV}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${SITE_ENV}"
  set +a
fi
CONFIG_DIR="${CONFIG_DIR:-${ROOT_DIR}/.config}"
export CONFIG_DIR
# shellcheck source=../../../scripts/terraform/bespoke_swarm_defaults.sh
source "${ROOT_DIR}/scripts/terraform/bespoke_swarm_defaults.sh"
homelab_bespoke_swarm_set_defaults "${CONFIG_DIR}" "${TERRAFORM_DIR}" "${ROOT_DIR}"
DEFAULT_CONFIG_TFVARS="${DEFAULT_SLICE_TFVARS}"

CONFIG_TFVARS="${NPM_CONFIG_TFVARS:-${DEFAULT_CONFIG_TFVARS}}"
BACKEND_CONFIG="${NPM_CONFIG_BACKEND:-${DEFAULT_BACKEND}}"

usage() {
  cat <<USAGE
Usage: pipelines/terraform/swarm/nginx_proxy_manager/config.sh [options] [config_tfvars] [backend_config]

Apply Nginx Proxy Manager certificates and proxy hosts via the NPM API (terraform init, plan, apply).

Options:
  --tfvars <path>           Config slice settings (default: ${DEFAULT_CONFIG_TFVARS})
  --backend <path>          S3 backend config (default: ${DEFAULT_BACKEND})
  -h, --help                Show this help

Environment overrides: NPM_CONFIG_TFVARS, NPM_CONFIG_BACKEND, CONFIG_DIR (from .config/docker/site.env)
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

run_terraform_init_in_dir() {
  local tf_dir="$1"
  shift
  local init_log
  init_log="$(mktemp -t npm-terraform-init-XXXXXX)"

  if (
    cd "${tf_dir}"
    terraform init -backend-config="${BACKEND_CONFIG}" "$@" \
      > >(tee "${init_log}") \
      2> >(tee -a "${init_log}" >&2)
  ); then
    rm -f "${init_log}"
    return 0
  fi

  if grep -q "Backend configuration changed" "${init_log}"; then
    if [[ -f "${tf_dir}/.terraform/terraform.tfstate" ]]; then
      echo "[WARN] Backend change detected in ${tf_dir}; attempting state migration"
      if (
        cd "${tf_dir}"
        terraform init -force-copy -migrate-state -backend-config="${BACKEND_CONFIG}" "$@"
      ); then
        rm -f "${init_log}"
        return 0
      fi
    fi
    echo "[WARN] Backend change detected in ${tf_dir}; re-running terraform init -reconfigure"
    if (
      cd "${tf_dir}"
      terraform init -reconfigure -backend-config="${BACKEND_CONFIG}" "$@"
    ); then
      rm -f "${init_log}"
      return 0
    fi
  fi

  rm -f "${init_log}"
  return 1
}

ensure_app_state_exists() {
  echo "[INFO] Verifying app remote state exists before running config stage"
  if ! run_terraform_init_in_dir "${APP_TERRAFORM_DIR}"; then
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
require_file "backend config" "${BACKEND_CONFIG}"

echo "Terraform dir:     ${TERRAFORM_DIR}"
echo "Config tfvars:     ${CONFIG_TFVARS}"
echo "Backend config:    ${BACKEND_CONFIG}"

ensure_app_state_exists

cd "${TERRAFORM_DIR}"

echo "[STEP] terraform init (Nginx Proxy Manager config)"
if ! run_terraform_init_in_dir "${TERRAFORM_DIR}"; then
  echo "[ERR] terraform init failed" >&2
  exit 1
fi

PLAN_ARGS=(
  -input=false
  -var-file "${CONFIG_TFVARS}"
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
