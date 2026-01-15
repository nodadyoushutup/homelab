#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR_FOR_STAGE="${SCRIPT_DIR:-}"
ROOT_DIR="${ROOT_DIR:-}"
PIPELINE_SCRIPT_ROOT="${PIPELINE_SCRIPT_ROOT:-}"
SERVICE_NAME="${SERVICE_NAME:-}"
STAGE_NAME="${STAGE_NAME:-}"
ENTRYPOINT_RELATIVE="${ENTRYPOINT_RELATIVE:-${SERVICE_NAME}}"
TERRAFORM_DIR="${TERRAFORM_DIR:-}"
DEFAULT_TFVARS_BASENAME="${DEFAULT_TFVARS_BASENAME:-${SERVICE_NAME}}"
DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE:-${HOME}/.tfvars/${DEFAULT_TFVARS_BASENAME}.tfvars}"
DEFAULT_BACKEND_FILE="${DEFAULT_BACKEND_FILE:-${HOME}/.tfvars/minio.backend.hcl}"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${HOME}/.tfvars}"

if [[ -z "${SCRIPT_DIR_FOR_STAGE}" || -z "${ROOT_DIR}" || -z "${PIPELINE_SCRIPT_ROOT}" ]]; then
  echo "[ERR] Stage script must define SCRIPT_DIR, ROOT_DIR, and PIPELINE_SCRIPT_ROOT before sourcing swarm_pipeline.sh" >&2
  exit 1
fi

if [[ -z "${SERVICE_NAME}" || -z "${STAGE_NAME}" ]]; then
  echo "[ERR] Stage script must define SERVICE_NAME and STAGE_NAME before sourcing swarm_pipeline.sh" >&2
  exit 1
fi

TERRAFORM_DIR="${TERRAFORM_DIR:-${ROOT_DIR}/terraform/swarm/${SERVICE_NAME}}"

ENV_SCRIPT="${PIPELINE_SCRIPT_ROOT}/env_check.sh"
RESOLVE_SCRIPT="${PIPELINE_SCRIPT_ROOT}/resolve_inputs.sh"
EXEC_SCRIPT="${PIPELINE_SCRIPT_ROOT}/terraform_exec.sh"

for helper in "${ENV_SCRIPT}" "${RESOLVE_SCRIPT}" "${EXEC_SCRIPT}"; do
  if [[ ! -x "${helper}" ]]; then
    echo "[ERR] Missing helper script: ${helper}" >&2
    exit 1
  fi
done

usage() {
  cat <<USAGE
Usage: ${ENTRYPOINT_RELATIVE} [--tfvars <path>] [--backend <path>] [tfvars_path] [backend_path]

Runs the ${STAGE_NAME} pipeline for ${SERVICE_NAME}.

Optional arguments can be provided either as flags or positional values.
If omitted, defaults are:
  TFVARS  -> ${DEFAULT_TFVARS_FILE}
  BACKEND -> ${DEFAULT_BACKEND_FILE}
USAGE
}

if ! declare -p PIPELINE_ARGS > /dev/null 2>&1; then
  PIPELINE_ARGS=()
fi

TFVARS_ARG=""
BACKEND_ARG=""

ARGS=("${PIPELINE_ARGS[@]}")
while [[ ${#ARGS[@]} -gt 0 ]]; do
  case "${ARGS[0]}" in
    --tfvars)
      if [[ ${#ARGS[@]} -lt 2 ]]; then
        echo "[ERR] --tfvars flag requires a path argument" >&2
        usage >&2
        exit 2
      fi
      TFVARS_ARG="${ARGS[1]}"
      ARGS=("${ARGS[@]:2}")
      ;;
    --backend)
      if [[ ${#ARGS[@]} -lt 2 ]]; then
        echo "[ERR] --backend flag requires a path argument" >&2
        usage >&2
        exit 2
      fi
      BACKEND_ARG="${ARGS[1]}"
      ARGS=("${ARGS[@]:2}")
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "${TFVARS_ARG}" ]]; then
        TFVARS_ARG="${ARGS[0]}"
      elif [[ -z "${BACKEND_ARG}" ]]; then
        BACKEND_ARG="${ARGS[0]}"
      else
        echo "[ERR] Unexpected argument: ${ARGS[0]}" >&2
        usage >&2
        exit 2
      fi
      ARGS=("${ARGS[@]:1}")
      ;;
  esac
done

PYTHON_CMD=""
FILTER_SCRIPT=""
FILTER_AVAILABLE="0"

ENV_OUTPUT="$("${ENV_SCRIPT}")" || exit 1
while IFS='=' read -r key value; do
  case "$key" in
    PYTHON_CMD) PYTHON_CMD="$value" ;;
    FILTER_SCRIPT) FILTER_SCRIPT="$value" ;;
    FILTER_AVAILABLE) FILTER_AVAILABLE="$value" ;;
  esac
done <<<"${ENV_OUTPUT}"

TFVARS_PATH=""
BACKEND_CONFIG_PATH=""

RESOLVE_OUTPUT="$(
  TFVARS_ARG="${TFVARS_ARG}" \
  BACKEND_ARG="${BACKEND_ARG}" \
  TERRAFORM_DIR="${TERRAFORM_DIR}" \
  DEFAULT_TFVARS_BASENAME="${DEFAULT_TFVARS_BASENAME}" \
  DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE}" \
  DEFAULT_BACKEND_FILE="${DEFAULT_BACKEND_FILE}" \
  TFVARS_HOME_DIR="${TFVARS_HOME_DIR}" \
  "${RESOLVE_SCRIPT}"
)" || exit 1
while IFS='=' read -r key value; do
  case "$key" in
    TFVARS_PATH) TFVARS_PATH="$value" ;;
    BACKEND_PATH) BACKEND_CONFIG_PATH="$value" ;;
  esac
done <<<"${RESOLVE_OUTPUT}"

if [[ -z "${TFVARS_PATH}" || ! -f "${TFVARS_PATH}" ]]; then
  echo "[ERR] Missing TFVARS file: ${TFVARS_PATH}" >&2
  exit 1
fi
if [[ -z "${BACKEND_CONFIG_PATH}" || ! -f "${BACKEND_CONFIG_PATH}" ]]; then
  echo "[ERR] Missing backend config file: ${BACKEND_CONFIG_PATH}" >&2
  exit 1
fi

echo "TFVARS file: ${TFVARS_PATH}"
echo "Backend config: ${BACKEND_CONFIG_PATH}"

if declare -F pipeline_pre_terraform > /dev/null; then
  pipeline_pre_terraform
fi

cd "${TERRAFORM_DIR}"

export PYTHON_CMD FILTER_SCRIPT FILTER_AVAILABLE TFVARS_PATH BACKEND_CONFIG_PATH

run_terraform_init() {
  local init_args=("$@")
  local init_log
  init_log="$(mktemp -t terraform-init-XXXXXX)"

  if "${EXEC_SCRIPT}" init "${init_args[@]}" \
    > >(tee "${init_log}") \
    2> >(tee -a "${init_log}" >&2); then
    rm -f "${init_log}"
    return 0
  fi

  if grep -q "Backend configuration changed" "${init_log}"; then
    if [[ -f ".terraform/terraform.tfstate" ]]; then
      echo "[WARN] Backend change detected; attempting automatic state migration"
      if "${EXEC_SCRIPT}" init -force-copy -migrate-state "${init_args[@]}"; then
        rm -f "${init_log}"
        return 0
      fi
    fi

    echo "[WARN] Backend change detected; re-running terraform init with -reconfigure"
    if "${EXEC_SCRIPT}" init -reconfigure "${init_args[@]}"; then
      rm -f "${init_log}"
      return 0
    fi
  fi

  rm -f "${init_log}"
  return 1
}

echo "[STEP] terraform init (${STAGE_NAME})"
if ! run_terraform_init -backend-config="${BACKEND_CONFIG_PATH}"; then
  echo "[ERR] terraform init failed" >&2
  exit 1
fi

if ! declare -p PLAN_ARGS_EXTRA >/dev/null 2>&1; then
  PLAN_ARGS_EXTRA=()
fi
if ! declare -p APPLY_ARGS_EXTRA >/dev/null 2>&1; then
  APPLY_ARGS_EXTRA=()
fi

PLAN_ARGS=(-input=false -var-file "${TFVARS_PATH}")
PLAN_ARGS+=("${PLAN_ARGS_EXTRA[@]}")

APPLY_ARGS=(-input=false -auto-approve -var-file "${TFVARS_PATH}")
APPLY_ARGS+=("${APPLY_ARGS_EXTRA[@]}")

echo "[STAGE] ${STAGE_NAME} plan"
if ! "${EXEC_SCRIPT}" plan "${PLAN_ARGS[@]}"; then
  echo "[ERR] terraform plan (${STAGE_NAME}) failed" >&2
  exit 1
fi

echo "[STAGE] ${STAGE_NAME} apply"
if ! "${EXEC_SCRIPT}" apply "${APPLY_ARGS[@]}"; then
  echo "[ERR] terraform apply (${STAGE_NAME}) failed" >&2
  exit 1
fi

echo "[DONE] ${STAGE_NAME} apply complete."
