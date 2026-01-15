#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${PIPELINE_DIR}/.." && pwd)"

TFVARS_ARG="${TFVARS_ARG:-}"
BACKEND_ARG="${BACKEND_ARG:-}"
DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE:-}"
DEFAULT_TFVARS_BASENAME="${DEFAULT_TFVARS_BASENAME:-}"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${HOME}/.tfvars}"
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
  local candidate

  if [[ -n "${provided_path}" ]]; then
    candidate="${provided_path}"
    if [[ -f "${candidate}" ]]; then
      realpath "${candidate}"
      return 0
    else
      echo "[WARN] Provided TFVARS file not found: ${candidate}" >&2
    fi
  fi

  if [[ -n "${default_file}" ]]; then
    candidate="${default_file}"
    if [[ -f "${candidate}" ]]; then
      realpath "${candidate}"
      return 0
    else
      echo "[WARN] Default TFVARS file override not found: ${candidate}" >&2
    fi
  fi

  if [[ -n "${default_basename}" ]]; then
    candidate="${home_dir}/${default_basename}"
    if [[ "${candidate}" != *.tfvars ]]; then
      candidate="${candidate}.tfvars"
    fi
    if [[ -f "${candidate}" ]]; then
      realpath "${candidate}"
      return 0
    fi
  fi

  if [[ -d "${home_dir}" ]]; then
    candidate="$(find "${home_dir}" -maxdepth 1 -type f -name '*.tfvars' | sort | head -n 1 || true)"
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      realpath "${candidate}"
      return 0
    fi
  fi

  if [[ -d "${terraform_dir}" ]]; then
    candidate="$(find "${terraform_dir}" -maxdepth 1 -type f -name '*.tfvars' | sort | head -n 1 || true)"
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      realpath "${candidate}"
      return 0
    fi
  fi

  return 1
}

resolve_backend() {
  local provided_path="$1"
  local default_path="$2"
  local home_dir="$3"
  local candidate

  if [[ -n "${provided_path}" ]]; then
    candidate="${provided_path}"
    if [[ -f "${candidate}" ]]; then
      realpath "${candidate}"
      return 0
    else
      echo "[ERR] Provided backend config not found: ${candidate}" >&2
      return 2
    fi
  fi

  if [[ -n "${default_path}" ]]; then
    candidate="${default_path}"
    if [[ -f "${candidate}" ]]; then
      realpath "${candidate}"
      return 0
    else
      echo "[WARN] Default backend config override not found: ${candidate}" >&2
    fi
  fi

  if [[ -d "${home_dir}" ]]; then
    candidate="$(find "${home_dir}" -maxdepth 1 -type f \( -name '*.backend.hcl' -o -name 'backend.hcl' \) | sort | head -n 1 || true)"
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      realpath "${candidate}"
      return 0
    fi
  fi

  return 1
}

TFVARS_PATH=""
if TFVARS_PATH="$(resolve_tfvars "${TFVARS_ARG}" "${TERRAFORM_DIR}" "${DEFAULT_TFVARS_FILE}" "${DEFAULT_TFVARS_BASENAME}" "${TFVARS_HOME_DIR}")"; then
  :
else
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
  echo "[ERR] Unable to determine a backend config file" >&2
  exit 1
fi

echo "TFVARS_PATH=${TFVARS_PATH}"
echo "BACKEND_PATH=${BACKEND_PATH}"
