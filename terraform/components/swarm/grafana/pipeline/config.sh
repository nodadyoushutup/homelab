#!/usr/bin/env bash
# Bespoke Grafana config Swarm deploy (intentional during the AGENTS.md audit campaign).
# Bespoke self-contained entrypoint (shared *_pipeline.sh wrappers removed).
# Slice tfvars plus the Grafana provider credentials (config-id
# terraform/providers/grafana); no other shared swarm/dns/nfs var-files.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform/components/swarm/grafana/config"

CONFIG_DIR="${CONFIG_DIR:-${ROOT_DIR}/.config}"
export CONFIG_DIR

# shellcheck source=../../../scripts/terraform/resolve_config_by_id.sh
source "${ROOT_DIR}/scripts/terraform/resolve_config_by_id.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/terraform/terraform_backend_init.sh"
# shellcheck source=../../../scripts/terraform/grafana_tfvars_env.sh
source "${ROOT_DIR}/scripts/terraform/grafana_tfvars_env.sh"

SLICE_CONFIG_ID="$(homelab_config_id_from_terraform_dir "${ROOT_DIR}" "${TERRAFORM_DIR}")"
DEFAULT_SLICE_TFVARS="$(homelab_resolve_config_path "${CONFIG_DIR}" "${SLICE_CONFIG_ID}")"
DEFAULT_BACKEND="$(homelab_resolve_config_path "${CONFIG_DIR}" "terraform/minio.backend")"

SLICE_TFVARS="${GRAFANA_CONFIG_TFVARS:-${DEFAULT_SLICE_TFVARS}}"
BACKEND_CONFIG="${GRAFANA_CONFIG_BACKEND:-${DEFAULT_BACKEND}}"

usage() {
  cat <<USAGE
Usage: terraform/components/swarm/grafana/pipeline/config.sh [options] [slice_tfvars] [backend_config]

Deploy Grafana config on Docker Swarm (terraform init, plan, apply).

Options:
  --tfvars <path>           Slice tfvars (default: ${DEFAULT_SLICE_TFVARS})
  --backend <path>          S3 backend config (default: ${DEFAULT_BACKEND})
  -h, --help                Show this help

Environment overrides: GRAFANA_CONFIG_TFVARS, GRAFANA_CONFIG_BACKEND, CONFIG_DIR (default: <repo>/.config)
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

ARGS=("$@")
while [[ ${#ARGS[@]} -gt 0 ]]; do
  case "${ARGS[0]}" in
    --tfvars)
      [[ ${#ARGS[@]} -ge 2 ]] || {
        echo "[ERR] --tfvars requires a path" >&2
        exit 2
      }
      SLICE_TFVARS="${ARGS[1]}"
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
      if [[ -z "${POSITIONAL_SLICE_TFVARS:-}" ]]; then
        POSITIONAL_SLICE_TFVARS="${ARGS[0]}"
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

if [[ -n "${POSITIONAL_SLICE_TFVARS:-}" ]]; then
  SLICE_TFVARS="${POSITIONAL_SLICE_TFVARS}"
fi
if [[ -n "${POSITIONAL_BACKEND:-}" ]]; then
  BACKEND_CONFIG="${POSITIONAL_BACKEND}"
fi

if [[ -n "${TFVARS_FILE:-}" ]]; then
  SLICE_TFVARS="${TFVARS_FILE}"
fi
if [[ -n "${BACKEND_FILE:-}" ]]; then
  BACKEND_CONFIG="${BACKEND_FILE}"
fi

require_terraform
require_file "slice tfvars" "${SLICE_TFVARS}"
require_file "grafana credentials tfvars" "${GRAFANA_TFVARS}"

echo "Terraform dir:     ${TERRAFORM_DIR}"
echo "Slice tfvars:      ${SLICE_TFVARS}"
echo "Grafana creds:     ${GRAFANA_TFVARS}"
echo "Backend config:    ${BACKEND_CONFIG}"

cd "${TERRAFORM_DIR}"


echo "[STEP] terraform init (Grafana config)"
if ! homelab_terraform_init "${TERRAFORM_DIR}"; then
  echo "[ERR] terraform init failed" >&2
  exit 1
fi

PLAN_ARGS=(
  -input=false
  -var-file "${SLICE_TFVARS}"
  -var-file "${GRAFANA_TFVARS}"
)

echo "[STEP] terraform plan (Grafana config)"
if ! terraform plan "${PLAN_ARGS[@]}"; then
  echo "[ERR] terraform plan failed" >&2
  exit 1
fi

echo "[STEP] terraform apply (Grafana config)"
if ! terraform apply -input=false -auto-approve "${PLAN_ARGS[@]}"; then
  echo "[ERR] terraform apply failed" >&2
  exit 1
fi

echo "[DONE] Grafana config apply complete."
