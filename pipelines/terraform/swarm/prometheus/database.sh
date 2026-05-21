#!/usr/bin/env bash
# Bespoke Prometheus database (VictoriaMetrics) Swarm deploy — no shared swarm_pipeline / scripts/terraform helpers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/prometheus/database"

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
DEFAULT_DATABASE_TFVARS="${DEFAULT_SLICE_TFVARS}"

DOCKER_TFVARS="${SWARM_DOCKER_PROVIDER_TFVARS:-${PROMETHEUS_DATABASE_DOCKER_TFVARS:-${DEFAULT_DOCKER_TFVARS}}}"
DNS_TFVARS="${SWARM_DNS_PROVIDER_TFVARS:-${PROMETHEUS_DATABASE_DNS_TFVARS:-${DEFAULT_DNS_TFVARS}}}"
DATABASE_TFVARS="${PROMETHEUS_DATABASE_TFVARS:-${DEFAULT_DATABASE_TFVARS}}"
BACKEND_CONFIG="${PROMETHEUS_DATABASE_BACKEND:-${DEFAULT_BACKEND}}"

usage() {
  cat <<USAGE
Usage: pipelines/terraform/swarm/prometheus/database.sh [options] [database_tfvars] [backend_config]

Deploy VictoriaMetrics (Prometheus database) on Docker Swarm (terraform init, plan, apply).

Options:
  --docker-tfvars <path>    Swarm Docker provider (default: ${DEFAULT_DOCKER_TFVARS})
  --dns-tfvars <path>       Shared dns_nameservers (default: ${DEFAULT_DNS_TFVARS})
  --tfvars <path>           Stack settings (default: ${DEFAULT_DATABASE_TFVARS})
  --backend <path>          S3 backend config (default: ${DEFAULT_BACKEND})
  -h, --help                Show this help

Environment overrides: SWARM_DOCKER_PROVIDER_TFVARS, SWARM_DNS_PROVIDER_TFVARS, PROMETHEUS_DATABASE_TFVARS, PROMETHEUS_DATABASE_BACKEND, CONFIG_DIR (from .config/docker/site.env)
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
    --docker-tfvars)
      [[ ${#ARGS[@]} -ge 2 ]] || {
        echo "[ERR] --docker-tfvars requires a path" >&2
        exit 2
      }
      DOCKER_TFVARS="${ARGS[1]}"
      ARGS=("${ARGS[@]:2}")
      ;;
    --dns-tfvars)
      [[ ${#ARGS[@]} -ge 2 ]] || {
        echo "[ERR] --dns-tfvars requires a path" >&2
        exit 2
      }
      DNS_TFVARS="${ARGS[1]}"
      ARGS=("${ARGS[@]:2}")
      ;;
    --tfvars)
      [[ ${#ARGS[@]} -ge 2 ]] || {
        echo "[ERR] --tfvars requires a path" >&2
        exit 2
      }
      DATABASE_TFVARS="${ARGS[1]}"
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
      if [[ -z "${POSITIONAL_DATABASE_TFVARS:-}" ]]; then
        POSITIONAL_DATABASE_TFVARS="${ARGS[0]}"
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

if [[ -n "${POSITIONAL_DATABASE_TFVARS:-}" ]]; then
  DATABASE_TFVARS="${POSITIONAL_DATABASE_TFVARS}"
fi
if [[ -n "${POSITIONAL_BACKEND:-}" ]]; then
  BACKEND_CONFIG="${POSITIONAL_BACKEND}"
fi

# Jenkins optional parameters (empty = use defaults above).
if [[ -n "${TFVARS_FILE:-}" ]]; then
  DATABASE_TFVARS="${TFVARS_FILE}"
fi
if [[ -n "${BACKEND_FILE:-}" ]]; then
  BACKEND_CONFIG="${BACKEND_FILE}"
fi

require_terraform
require_file "docker provider tfvars" "${DOCKER_TFVARS}"
require_file "dns provider tfvars" "${DNS_TFVARS}"
require_file "database tfvars" "${DATABASE_TFVARS}"
require_file "backend config" "${BACKEND_CONFIG}"

echo "Terraform dir:     ${TERRAFORM_DIR}"
echo "Docker tfvars:     ${DOCKER_TFVARS}"
echo "DNS tfvars:        ${DNS_TFVARS}"
echo "Database tfvars:   ${DATABASE_TFVARS}"
echo "Backend config:    ${BACKEND_CONFIG}"

cd "${TERRAFORM_DIR}"

run_terraform_init() {
  local init_log
  init_log="$(mktemp -t prometheus-database-terraform-init-XXXXXX)"

  if terraform init -backend-config="${BACKEND_CONFIG}" "$@" \
    > >(tee "${init_log}") \
    2> >(tee -a "${init_log}" >&2); then
    rm -f "${init_log}"
    return 0
  fi

  if grep -q "Backend configuration changed" "${init_log}"; then
    if [[ -f ".terraform/terraform.tfstate" ]]; then
      echo "[WARN] Backend change detected; attempting state migration"
      if terraform init -force-copy -migrate-state -backend-config="${BACKEND_CONFIG}" "$@"; then
        rm -f "${init_log}"
        return 0
      fi
    fi
    echo "[WARN] Backend change detected; re-running terraform init -reconfigure"
    if terraform init -reconfigure -backend-config="${BACKEND_CONFIG}" "$@"; then
      rm -f "${init_log}"
      return 0
    fi
  fi

  rm -f "${init_log}"
  return 1
}

echo "[STEP] terraform init (Prometheus database / VictoriaMetrics)"
if ! run_terraform_init; then
  echo "[ERR] terraform init failed" >&2
  exit 1
fi

PLAN_ARGS=(
  -input=false
  -var-file "${DOCKER_TFVARS}"
  -var-file "${DNS_TFVARS}"
  -var-file "${DATABASE_TFVARS}"
)

echo "[STEP] terraform plan (Prometheus database / VictoriaMetrics)"
if ! terraform plan "${PLAN_ARGS[@]}"; then
  echo "[ERR] terraform plan failed" >&2
  exit 1
fi

echo "[STEP] terraform apply (Prometheus database / VictoriaMetrics)"
if ! terraform apply -input=false -auto-approve "${PLAN_ARGS[@]}"; then
  echo "[ERR] terraform apply failed" >&2
  exit 1
fi

echo "[DONE] Prometheus database (VictoriaMetrics) apply complete."
