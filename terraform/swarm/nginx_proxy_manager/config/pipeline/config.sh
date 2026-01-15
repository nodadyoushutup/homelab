#!/usr/bin/env bash
# Stage 2 (docs/planning/nginx-proxy-manager-plan.md) – config stage hooks the NPM API
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/pipeline"

SERVICE_NAME="nginx_proxy_manager"
STAGE_NAME="Nginx Proxy Manager config"
ENTRYPOINT_RELATIVE="terraform/swarm/nginx_proxy_manager/config/pipeline/config.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/nginx_proxy_manager/config"

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${HOME}/.tfvars}"
DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE:-${TFVARS_HOME_DIR}/nginx-proxy-manager/config.tfvars}"
DEFAULT_BACKEND_FILE="${DEFAULT_BACKEND_FILE:-${TFVARS_HOME_DIR}/minio.backend.hcl}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=("-parallelism=1")

PIPELINE_ARGS=("$@")

terraform_init_with_migration() {
  local tf_dir="$1"
  shift
  local init_args=("$@")
  local init_log

  init_log="$(mktemp -t terraform-init-app-XXXXXX)"
  if "${PIPELINE_SCRIPT_ROOT}/terraform_exec.sh" -chdir="${tf_dir}" init "${init_args[@]}" \
    > >(tee "${init_log}") \
    2> >(tee -a "${init_log}" >&2); then
    rm -f "${init_log}"
    return 0
  fi

  if grep -q "Backend configuration changed" "${init_log}"; then
    echo "[WARN] App backend change detected; attempting automatic migration"
    if "${PIPELINE_SCRIPT_ROOT}/terraform_exec.sh" -chdir="${tf_dir}" init -force-copy -migrate-state "${init_args[@]}"; then
      rm -f "${init_log}"
      return 0
    fi

    echo "[WARN] App backend change still failing; retrying with -reconfigure"
    if "${PIPELINE_SCRIPT_ROOT}/terraform_exec.sh" -chdir="${tf_dir}" init -reconfigure "${init_args[@]}"; then
      rm -f "${init_log}"
      return 0
    fi
  fi

  rm -f "${init_log}"
  return 1
}

set_remote_state_backend_var() {
  if [[ -z "${BACKEND_CONFIG_PATH:-}" || ! -f "${BACKEND_CONFIG_PATH}" ]]; then
    echo "[ERR] Backend config path unavailable; cannot derive remote_state_backend" >&2
    exit 1
  fi

  local python_bin="${PYTHON_CMD:-python3}"
  if ! command -v "${python_bin}" >/dev/null 2>&1; then
    echo "[ERR] python3 is required to render remote_state_backend for config stage" >&2
    exit 1
  fi

  local json_output
  if ! json_output="$(
    BACKEND_FILE="${BACKEND_CONFIG_PATH}" "${python_bin}" <<'PY'
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
    echo "[ERR] Failed to render remote_state_backend map from ${BACKEND_CONFIG_PATH}" >&2
    exit 1
  fi

  export TF_VAR_remote_state_backend="${json_output}"
}

ensure_app_state_exists() {
  local app_tf_dir="${ROOT_DIR}/terraform/swarm/nginx_proxy_manager/app"
  local init_args=(-input=false -backend-config "${BACKEND_CONFIG_PATH}")

  echo "[INFO] Verifying app remote state exists before running config stage"
  if ! terraform_init_with_migration "${app_tf_dir}" "${init_args[@]}"; then
    echo "[ERR] Unable to initialize app Terraform state. Run the app stage before config." >&2
    exit 1
  fi

  if ! "${PIPELINE_SCRIPT_ROOT}/terraform_exec.sh" -chdir="${app_tf_dir}" state pull >/dev/null; then
    echo "[ERR] Failed to pull app state; ensure the app stage has been applied successfully." >&2
    exit 1
  fi
}

pipeline_pre_terraform() {
  set_remote_state_backend_var
  ensure_app_state_exists
}

source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
