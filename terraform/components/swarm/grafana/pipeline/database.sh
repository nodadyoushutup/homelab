#!/usr/bin/env bash
# Bespoke Grafana database Swarm deploy (intentional during the AGENTS.md audit campaign).
# Bespoke self-contained entrypoint (shared *_pipeline.sh wrappers removed).
# Single slice tfvars carries provider + DNS + stack settings (no shared swarm/dns var-files).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform/components/swarm/grafana/database"
APP_TERRAFORM_DIR="${ROOT_DIR}/terraform/components/swarm/grafana/app"

CONFIG_DIR="${CONFIG_DIR:-${ROOT_DIR}/.config}"
export CONFIG_DIR

# shellcheck source=../../../scripts/terraform/resolve_config_by_id.sh
source "${ROOT_DIR}/scripts/terraform/resolve_config_by_id.sh"

SLICE_CONFIG_ID="$(homelab_config_id_from_terraform_dir "${ROOT_DIR}" "${TERRAFORM_DIR}")"
DEFAULT_SLICE_TFVARS="$(homelab_resolve_config_path "${CONFIG_DIR}" "${SLICE_CONFIG_ID}")"
DEFAULT_BACKEND="$(homelab_resolve_config_path "${CONFIG_DIR}" "terraform/minio.backend")"

SLICE_TFVARS="${GRAFANA_DATABASE_TFVARS:-${DEFAULT_SLICE_TFVARS}}"
BACKEND_CONFIG="${GRAFANA_DATABASE_BACKEND:-${DEFAULT_BACKEND}}"

usage() {
  cat <<USAGE
Usage: terraform/components/swarm/grafana/pipeline/database.sh [options] [slice_tfvars] [backend_config]

Deploy Grafana database on Docker Swarm (terraform init, plan, apply).

Options:
  --tfvars <path>           Slice tfvars (default: ${DEFAULT_SLICE_TFVARS})
  --backend <path>          S3 backend config (default: ${DEFAULT_BACKEND})
  -h, --help                Show this help

Environment overrides: GRAFANA_DATABASE_TFVARS, GRAFANA_DATABASE_BACKEND, CONFIG_DIR (default: <repo>/.config)
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
  init_log="$(mktemp -t grafana-database-terraform-init-XXXXXX)"

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

set_remote_state_backend_var() {
  if [[ -z "${BACKEND_CONFIG}" || ! -f "${BACKEND_CONFIG}" ]]; then
    echo "[ERR] Backend config path unavailable; cannot derive remote_state_backend" >&2
    exit 1
  fi

  local python_bin="${PYTHON_CMD:-python3}"
  if ! command -v "${python_bin}" >/dev/null 2>&1; then
    echo "[ERR] python3 is required to render remote_state_backend for database stage" >&2
    exit 1
  fi

  local json_output
  if ! json_output="$(
    BACKEND_FILE="${BACKEND_CONFIG}" "${python_bin}" <<'PY'
import json
import os
import re
import sys

path = os.environ.get("BACKEND_FILE")
if not path or not os.path.exists(path):
    sys.stderr.write("Backend file not found\n")
    sys.exit(1)

token_re = re.compile(r'([A-Za-z0-9_-]+)\s*=\s*(".*?"|\{[^{}]*\}|[^,#\s]+)')

def parse_value(raw):
    val = raw.strip().rstrip(",")
    if val.startswith("{") and val.endswith("}"):
        inner = val[1:-1].strip()
        nested = {}
        if inner:
            for key, inner_val in token_re.findall(inner):
                nested[key] = parse_value(inner_val)
        return nested
    if val.startswith('"') and val.endswith('"'):
        return val[1:-1]
    if val.lower() in ("true", "false"):
        return val.lower() == "true"
    try:
        if "." in val:
            return float(val)
        return int(val)
    except ValueError:
        return val

data = {}
stack = [data]
with open(path, "r", encoding="utf-8") as handle:
    for raw_line in handle:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.endswith("{") and "=" not in line:
            block = line[:-1].strip()
            new_map = {}
            stack[-1][block] = new_map
            stack.append(new_map)
            continue
        if line == "}":
            if len(stack) == 1:
                sys.stderr.write("Unexpected closing brace in backend file\n")
                sys.exit(1)
            stack.pop()
            continue
        if "=" not in line:
            continue
        key, raw_val = [part.strip() for part in line.split("=", 1)]
        stack[-1][key] = parse_value(raw_val)

print(json.dumps(data))
PY
  )"; then
    echo "[ERR] Failed to render remote_state_backend map from ${BACKEND_CONFIG}" >&2
    exit 1
  fi

  export TF_VAR_remote_state_backend="${json_output}"
}

ensure_app_state_exists() {
  echo "[INFO] Verifying app remote state exists before running database stage"
  if ! run_terraform_init_in_dir "${APP_TERRAFORM_DIR}"; then
    echo "[ERR] Unable to initialize app Terraform state. Run the app stage before database." >&2
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
require_file "backend config" "${BACKEND_CONFIG}"

echo "Terraform dir:     ${TERRAFORM_DIR}"
echo "Slice tfvars:      ${SLICE_TFVARS}"
echo "Backend config:    ${BACKEND_CONFIG}"

set_remote_state_backend_var
ensure_app_state_exists

cd "${TERRAFORM_DIR}"

echo "[STEP] terraform init (Grafana database)"
if ! run_terraform_init_in_dir "${TERRAFORM_DIR}"; then
  echo "[ERR] terraform init failed" >&2
  exit 1
fi

PLAN_ARGS=(
  -input=false
  -var-file "${SLICE_TFVARS}"
)

echo "[STEP] terraform plan (Grafana database)"
if ! terraform plan "${PLAN_ARGS[@]}"; then
  echo "[ERR] terraform plan failed" >&2
  exit 1
fi

echo "[STEP] terraform apply (Grafana database)"
if ! terraform apply -input=false -auto-approve -parallelism=1 "${PLAN_ARGS[@]}"; then
  echo "[ERR] terraform apply failed" >&2
  exit 1
fi

echo "[DONE] Grafana database apply complete."
