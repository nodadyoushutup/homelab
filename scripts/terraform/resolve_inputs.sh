#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${PIPELINE_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load_root_env.sh"
# shellcheck source=resolve_config_by_id.sh
source "${SCRIPT_DIR}/resolve_config_by_id.sh"

TFVARS_ARG="${TFVARS_ARG:-}"
BACKEND_ARG="${BACKEND_ARG:-}"
DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE:-}"
DEFAULT_TFVARS_BASENAME="${DEFAULT_TFVARS_BASENAME:-}"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
DEFAULT_BACKEND_FILE="${DEFAULT_BACKEND_FILE:-}"
TERRAFORM_DIR="${TERRAFORM_DIR:-${ROOT_DIR}/terraform}"

if [[ $# -gt 0 ]]; then
  TFVARS_ARG="$1"
fi
if [[ $# -gt 1 ]]; then
  BACKEND_ARG="$2"
fi

resolve_tfvars() {
  local provided_path="$1"
  local terraform_dir="$2"
  local default_file="$3"
  local default_basename="$4"
  local home_dir="$5"
  local candidate=""
  local config_id=""
  local root_dir="${ROOT_DIR:-}"

  if [[ -n "${provided_path}" ]]; then
    candidate="${provided_path}"
    if [[ -f "${candidate}" ]]; then
      realpath "${candidate}"
      return 0
    fi
    echo "[WARN] Provided TFVARS file not found: ${candidate}" >&2
  fi

  if [[ -n "${default_file}" && -f "${default_file}" ]]; then
    realpath "${default_file}"
    return 0
  fi

  if config_id="$(homelab_config_id_from_terraform_dir "${root_dir}" "${terraform_dir}" 2>/dev/null)"; then
    if candidate="$(homelab_find_config_by_id "${home_dir}" "${config_id}" 2>/dev/null)"; then
      realpath "${candidate}"
      return 0
    fi
    candidate="$(homelab_resolve_config_path "${home_dir}" "${config_id}")"
    if [[ -f "${candidate}" ]]; then
      realpath "${candidate}"
      return 0
    fi
  fi

  if [[ -n "${default_basename}" ]]; then
    candidate="$(homelab_resolve_config_path "${home_dir}" "${default_basename}")"
    if [[ -f "${candidate}" ]]; then
      realpath "${candidate}"
      return 0
    fi
  fi

  if [[ -n "${default_file}" ]]; then
    echo "[WARN] Default TFVARS path not found: ${default_file}" >&2
    if [[ -n "${config_id}" ]]; then
      echo "[WARN] Expected first line: $(homelab_config_tag_line "${config_id}" | tr -d '\n')" >&2
    fi
  fi

  return 1
}

resolve_backend() {
  local provided_path="$1"
  local default_path="$2"
  local home_dir="$3"
  local candidate=""

  if [[ -n "${provided_path}" ]]; then
    candidate="${provided_path}"
    if [[ -f "${candidate}" ]]; then
      realpath "${candidate}"
      return 0
    fi
    echo "[ERR] Provided backend config not found: ${candidate}" >&2
    return 2
  fi

  if [[ -n "${default_path}" && -f "${default_path}" ]]; then
    realpath "${default_path}"
    return 0
  fi

  if candidate="$(homelab_find_config_by_id "${home_dir}" "minio.backend" 2>/dev/null)"; then
    realpath "${candidate}"
    return 0
  fi

  candidate="$(homelab_resolve_config_path "${home_dir}" "minio.backend")"
  if [[ -f "${candidate}" ]]; then
    realpath "${candidate}"
    return 0
  fi

  if [[ -n "${default_path}" ]]; then
    echo "[WARN] Default backend config not found: ${default_path}" >&2
    echo "[WARN] Expected first line: $(homelab_config_tag_line "minio.backend" | tr -d '\n')" >&2
  fi

  return 1
}

emit_shared_config_hint() {
  local home_dir="$1"

  if [[ -d "${home_dir}" ]]; then
    return 0
  fi

  echo "[ERR] TFVARS home directory not found: ${home_dir}" >&2
  if [[ "${home_dir}" == "/mnt/eapp/config"* ]] || [[ "${home_dir}" == *"/homelab/.config"* ]]; then
    echo "[ERR] Expected TFVARS_HOME_DIR / CONFIG_DIR (default: <homelab>/.config) to exist." >&2
    echo "[ERR] On Jenkins agents, bind-mount that host directory to match TFVARS_HOME_DIR." >&2
  fi
}

TFVARS_PATH=""
if TFVARS_PATH="$(resolve_tfvars "${TFVARS_ARG}" "${TERRAFORM_DIR}" "${DEFAULT_TFVARS_FILE}" "${DEFAULT_TFVARS_BASENAME}" "${TFVARS_HOME_DIR}")"; then
  :
else
  emit_shared_config_hint "${TFVARS_HOME_DIR}"
  echo "[ERR] Unable to determine a TFVARS file" >&2
  exit 1
fi

BACKEND_PATH=""
BACKEND_STATUS=0
if BACKEND_PATH="$(resolve_backend "${BACKEND_ARG}" "${DEFAULT_BACKEND_FILE}" "${TFVARS_HOME_DIR}")"; then
  :
else
  BACKEND_STATUS=$?
  if [[ ${BACKEND_STATUS} -eq 2 ]]; then
    exit 1
  fi
  emit_shared_config_hint "${TFVARS_HOME_DIR}"
  echo "[ERR] Unable to determine a backend config file" >&2
  exit 1
fi

echo "TFVARS_PATH=${TFVARS_PATH}"
echo "BACKEND_PATH=${BACKEND_PATH}"
