#!/usr/bin/env bash
# Bespoke GitHub Actions AMD64 runner deploy (intentional during the AGENTS.md audit campaign).
# Self-contained entrypoint — do not migrate onto shared *_pipeline.sh mid-audit.
# Single slice tfvars only (no shared provider/DNS/NFS var-files).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform/components/swarm/gha-runner-amd64/app"

CONFIG_DIR="${CONFIG_DIR:-${ROOT_DIR}/.config}"
export CONFIG_DIR

# shellcheck source=../../../scripts/terraform/resolve_config_by_id.sh
source "${ROOT_DIR}/scripts/terraform/resolve_config_by_id.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/terraform/terraform_backend_init.sh"
# Shared Docker provider catalog (config-id: terraform/providers/docker); exports DOCKER_TFVARS.
# shellcheck source=../../../scripts/terraform/docker_tfvars_env.sh
source "${ROOT_DIR}/scripts/terraform/docker_tfvars_env.sh"
# Shared NFS catalog (config-id: terraform/nfs); exports NFS_TFVARS.
# shellcheck source=../../../../scripts/terraform/nfs_tfvars_env.sh
source "${ROOT_DIR}/scripts/terraform/nfs_tfvars_env.sh"

SLICE_CONFIG_ID="$(homelab_config_id_from_terraform_dir "${ROOT_DIR}" "${TERRAFORM_DIR}")"
DEFAULT_SLICE_TFVARS="$(homelab_resolve_config_path "${CONFIG_DIR}" "${SLICE_CONFIG_ID}")"
DEFAULT_BACKEND="$(homelab_resolve_config_path "${CONFIG_DIR}" "terraform/minio.backend")"

SLICE_TFVARS="${GHA_RUNNER_AMD64_APP_TFVARS:-${DEFAULT_SLICE_TFVARS}}"
BACKEND_CONFIG="${GHA_RUNNER_AMD64_APP_BACKEND:-${DEFAULT_BACKEND}}"

usage() {
  cat <<USAGE
Usage: terraform/components/swarm/gha-runner-amd64/pipeline/app.sh [options] [slice_tfvars] [backend_config]

Deploy GitHub Actions AMD64 runner (terraform init, plan, apply).

Options:
  --tfvars <path>           Slice tfvars (default: ${DEFAULT_SLICE_TFVARS})
  --backend <path>          S3 backend config (default: ${DEFAULT_BACKEND})
  -h, --help                Show this help

Environment overrides: GHA_RUNNER_AMD64_APP_TFVARS, GHA_RUNNER_AMD64_APP_BACKEND, CONFIG_DIR (default: <repo>/.config)
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
      [[ ${#ARGS[@]} -ge 2 ]] || { echo "[ERR] --tfvars requires a path" >&2; exit 2; }
      SLICE_TFVARS="${ARGS[1]}"
      ARGS=("${ARGS[@]:2}")
      ;;
    --backend)
      [[ ${#ARGS[@]} -ge 2 ]] || { echo "[ERR] --backend requires a path" >&2; exit 2; }
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

[[ -n "${POSITIONAL_SLICE_TFVARS:-}" ]] && SLICE_TFVARS="${POSITIONAL_SLICE_TFVARS}"
[[ -n "${POSITIONAL_BACKEND:-}" ]] && BACKEND_CONFIG="${POSITIONAL_BACKEND}"
[[ -n "${TFVARS_FILE:-}" ]] && SLICE_TFVARS="${TFVARS_FILE}"
[[ -n "${BACKEND_FILE:-}" ]] && BACKEND_CONFIG="${BACKEND_FILE}"

require_terraform
require_file "slice tfvars" "${SLICE_TFVARS}"
require_file "docker providers tfvars" "${DOCKER_TFVARS}"
require_file "nfs catalog tfvars" "${NFS_TFVARS}"

echo "Terraform dir:     ${TERRAFORM_DIR}"
echo "Slice tfvars:      ${SLICE_TFVARS}"
echo "Backend config:    ${BACKEND_CONFIG}"

cd "${TERRAFORM_DIR}"


echo "[STEP] terraform init (GitHub Actions AMD64 runner)"
if ! homelab_terraform_init "${TERRAFORM_DIR}"; then
  echo "[ERR] terraform init failed" >&2
  exit 1
fi

PLAN_ARGS=(
  -input=false
  -var-file "${DOCKER_TFVARS}"
  -var-file "${SLICE_TFVARS}"
  -var-file "${NFS_TFVARS}"
)

echo "[STEP] terraform plan (GitHub Actions AMD64 runner)"
if ! terraform plan "${PLAN_ARGS[@]}"; then
  echo "[ERR] terraform plan failed" >&2
  exit 1
fi

echo "[STEP] terraform apply (GitHub Actions AMD64 runner)"
if ! terraform apply -input=false -auto-approve "${PLAN_ARGS[@]}"; then
  echo "[ERR] terraform apply failed" >&2
  exit 1
fi

echo "[DONE] GitHub Actions AMD64 runner apply complete."
