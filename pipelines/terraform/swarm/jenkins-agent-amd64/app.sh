#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="jenkins-agent-amd64"
STAGE_NAME="Jenkins agent amd64 app"
ENTRYPOINT_RELATIVE="pipelines/terraform/swarm/jenkins-agent-amd64/app.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/jenkins-agent-amd64/app"

JENKINS_AGENT_AMD64_TFVARS_DIR="${JENKINS_AGENT_AMD64_TFVARS_DIR:-${CONFIG_DIR:-/mnt/eapp/config}/jenkins-agent-amd64}"
DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE:-${JENKINS_AGENT_AMD64_TFVARS_DIR}/app.tfvars}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

CONTROLLER_TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/jenkins-controller/app"
EXPECTED_IMAGE_ARCH="amd64"
TERRAFORM_CONSOLE_READY="0"
REGISTRY_AUTH_ADDRESS=""
REGISTRY_AUTH_USERNAME=""
REGISTRY_AUTH_PASSWORD=""

ensure_terraform_console_ready() {
  if [[ "${TERRAFORM_CONSOLE_READY}" == "1" ]]; then
    return 0
  fi

  if ! terraform -chdir="${TERRAFORM_DIR}" init -backend=false -input=false > /dev/null; then
    echo "[ERR] Unable to initialize ${TERRAFORM_DIR} for Jenkins agent image validation." >&2
    exit 1
  fi

  TERRAFORM_CONSOLE_READY="1"
}

terraform_console_string() {
  local expression="$1"
  local console_output
  local python_cmd="${PYTHON_CMD:-python3}"
  local -a var_args=()

  ensure_terraform_console_ready

  if [[ -n "${DOCKER_PROVIDER_TFVARS_PATH:-}" && -f "${DOCKER_PROVIDER_TFVARS_PATH}" ]]; then
    var_args+=(-var-file "${DOCKER_PROVIDER_TFVARS_PATH}")
  fi
  var_args+=(-var-file "${TFVARS_PATH}")

  if ! console_output="$(
    printf '%s\n' "${expression}" | terraform -chdir="${TERRAFORM_DIR}" console "${var_args[@]}" 2>/dev/null
  )"; then
    echo "[ERR] Unable to evaluate Terraform expression for Jenkins agent validation: ${expression}" >&2
    exit 1
  fi

  if [[ -z "${console_output}" ]]; then
    printf '\n'
    return 0
  fi

  printf '%s' "${console_output}" | "${python_cmd}" -c 'import json, sys; value = json.loads(sys.stdin.read()); print("" if value is None else value)'
}

resolve_agent_image_from_terraform() {
  local agent_image
  agent_image="$(terraform_console_string 'var.agent_image')"

  if [[ -z "${agent_image}" ]]; then
    echo "[ERR] Unable to resolve Jenkins agent image from Terraform input agent_image." >&2
    exit 1
  fi

  printf '%s\n' "${agent_image}"
}

load_registry_auth_from_terraform() {
  if [[ -n "${REGISTRY_AUTH_USERNAME}" || -n "${REGISTRY_AUTH_PASSWORD}" || -n "${REGISTRY_AUTH_ADDRESS}" ]]; then
    return 0
  fi

  local agent_image reg_host auths_json python_cmd
  python_cmd="${PYTHON_CMD:-python3}"
  agent_image="$(resolve_agent_image_from_terraform)"
  reg_host="$(registry_address_from_image "${agent_image}")"
  if [[ -z "${reg_host}" ]]; then
    reg_host="docker.io"
  fi

  local -a var_args=()
  if [[ -n "${DOCKER_PROVIDER_TFVARS_PATH:-}" && -f "${DOCKER_PROVIDER_TFVARS_PATH}" ]]; then
    var_args+=(-var-file "${DOCKER_PROVIDER_TFVARS_PATH}")
  fi
  var_args+=(-var-file "${TFVARS_PATH}")

  auths_json="$(printf '%s\n' 'jsonencode(local.docker_registry_auths)' | terraform -chdir="${TERRAFORM_DIR}" console "${var_args[@]}" 2>/dev/null || true)"
  if [[ -z "${auths_json}" ]]; then
    return 0
  fi

  local -a _creds=()
  mapfile -t _creds < <(
    REG_HOST="${reg_host}" "${python_cmd}" <<'PY' <<<"${auths_json}"
import json, os, sys
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    auths = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(0)
if not isinstance(auths, list) or not auths:
    sys.exit(0)
reg = os.environ.get("REG_HOST", "").lower().strip()
pick = None
for a in auths:
    addr = (a.get("address") or "ghcr.io").lower()
    if addr == reg:
        pick = a
        break
if pick is None:
    pick = auths[0]
print(pick.get("address") or "")
print(pick.get("username") or "")
print(pick.get("password") or "")
PY
  ) || true
  if [[ ${#_creds[@]} -lt 3 ]]; then
    return 0
  fi
  REGISTRY_AUTH_ADDRESS="${_creds[0]}"
  REGISTRY_AUTH_USERNAME="${_creds[1]}"
  REGISTRY_AUTH_PASSWORD="${_creds[2]}"
}

registry_address_from_image() {
  local image_ref="$1"
  local registry_candidate="${image_ref%%/*}"

  case "${registry_candidate}" in
    *.*|*:*|localhost)
      printf '%s\n' "${registry_candidate}"
      ;;
    *)
      printf '\n'
      ;;
  esac
}

inspect_agent_image_manifest() {
  local agent_image="$1"
  local manifest_output
  local inspect_error=""
  local registry_address=""
  local temp_docker_config=""
  local docker_login_error=""

  if manifest_output="$(docker manifest inspect "${agent_image}" 2>&1)"; then
    printf '%s\n' "${manifest_output}"
    return 0
  fi
  inspect_error="${manifest_output}"

  load_registry_auth_from_terraform
  if [[ -z "${REGISTRY_AUTH_USERNAME}" || -z "${REGISTRY_AUTH_PASSWORD}" ]]; then
    echo "[ERR] Unable to inspect manifest for ${agent_image}. Anonymous registry access failed and no stage registry_auth credentials are configured." >&2
    if [[ -n "${inspect_error}" ]]; then
      echo "[ERR] docker manifest inspect: $(printf '%s' "${inspect_error}" | tr '\n' ' ')" >&2
    fi
    return 1
  fi

  registry_address="${REGISTRY_AUTH_ADDRESS:-$(registry_address_from_image "${agent_image}")}"
  if [[ -z "${registry_address}" ]]; then
    echo "[ERR] Unable to determine a registry address for ${agent_image} during manifest validation." >&2
    return 1
  fi

  temp_docker_config="$(mktemp -d -t docker-config-XXXXXX)"

  if ! docker_login_error="$(
    printf '%s' "${REGISTRY_AUTH_PASSWORD}" | DOCKER_CONFIG="${temp_docker_config}" docker login "${registry_address}" \
      --username "${REGISTRY_AUTH_USERNAME}" \
      --password-stdin 2>&1
  )"; then
    rm -rf "${temp_docker_config}"
    echo "[ERR] Unable to authenticate to ${registry_address} for Jenkins agent image validation." >&2
    echo "[ERR] docker login: $(printf '%s' "${docker_login_error}" | tr '\n' ' ')" >&2
    return 1
  fi

  if ! manifest_output="$(DOCKER_CONFIG="${temp_docker_config}" docker manifest inspect "${agent_image}" 2>&1)"; then
    rm -rf "${temp_docker_config}"
    echo "[ERR] Unable to inspect manifest for ${agent_image} after authenticating to ${registry_address}." >&2
    echo "[ERR] docker manifest inspect: $(printf '%s' "${manifest_output}" | tr '\n' ' ')" >&2
    return 1
  fi

  rm -rf "${temp_docker_config}"
  printf '%s\n' "${manifest_output}"
}

assert_agent_image_architecture() {
  local agent_image manifest_output
  agent_image="$(resolve_agent_image_from_terraform)"

  if ! command -v docker >/dev/null 2>&1; then
    echo "[ERR] docker is required to validate Jenkins agent image manifests." >&2
    exit 1
  fi

  echo "[INFO] Validating Jenkins agent image supports ${EXPECTED_IMAGE_ARCH}: ${agent_image}"
  if ! manifest_output="$(inspect_agent_image_manifest "${agent_image}")"; then
    exit 1
  fi

  if ! printf '%s\n' "${manifest_output}" | grep -q "\"architecture\"[[:space:]]*:[[:space:]]*\"${EXPECTED_IMAGE_ARCH}\""; then
    echo "[ERR] Jenkins agent image ${agent_image} does not advertise ${EXPECTED_IMAGE_ARCH} support." >&2
    exit 1
  fi
}

pipeline_pre_terraform() {
  if [[ ! -d "${CONTROLLER_TERRAFORM_DIR}" ]]; then
    echo "[ERR] Missing controller Terraform directory at ${CONTROLLER_TERRAFORM_DIR}. Run the controller pipeline first." >&2
    exit 1
  fi

  echo "[INFO] Checking Jenkins controller outputs"
  if ! terraform -chdir="${CONTROLLER_TERRAFORM_DIR}" init -backend-config="${BACKEND_CONFIG_PATH}" > /dev/null; then
    echo "[ERR] Unable to initialize controller backend; ensure controller pipeline has been run." >&2
    exit 1
  fi

  local controller_service_id
  controller_service_id="$(terraform -chdir="${CONTROLLER_TERRAFORM_DIR}" output -raw controller_service_id 2>/dev/null || true)"

  if [[ -z "${controller_service_id}" ]]; then
    echo "[ERR] Jenkins controller outputs unavailable. Run the controller pipeline before deploying agents." >&2
    exit 1
  fi

  assert_agent_image_architecture
}

PIPELINE_ARGS=("$@")


# shellcheck source=/dev/null
source "${PIPELINE_SCRIPT_ROOT}/swarm_docker_provider_tfvars_env.sh"
source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
