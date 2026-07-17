#!/usr/bin/env bash
# Bespoke Jenkins agent arm64 deploy (intentional during the AGENTS.md audit campaign).
# Bespoke self-contained entrypoint (shared *_pipeline.sh wrappers removed).
# Single slice tfvars carries pool docker provider + DNS/NFS + stack settings.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform/components/swarm/jenkins-agent-arm64/app"

SITE_ENV="${ROOT_DIR}/.config/docker/site.env"
if [[ -f "${SITE_ENV}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${SITE_ENV}"
  set +a
fi
CONFIG_DIR="${CONFIG_DIR:-${ROOT_DIR}/.config}"
export CONFIG_DIR

# shellcheck source=../../../scripts/terraform/resolve_config_by_id.sh
source "${ROOT_DIR}/scripts/terraform/resolve_config_by_id.sh"

SLICE_CONFIG_ID="$(homelab_config_id_from_terraform_dir "${ROOT_DIR}" "${TERRAFORM_DIR}")"
DEFAULT_SLICE_TFVARS="$(homelab_resolve_config_path "${CONFIG_DIR}" "${SLICE_CONFIG_ID}")"
DEFAULT_BACKEND="$(homelab_resolve_config_path "${CONFIG_DIR}" "terraform/minio.backend")"

SLICE_TFVARS="${JENKINS_AGENT_ARM64_APP_TFVARS:-${DEFAULT_SLICE_TFVARS}}"
BACKEND_CONFIG="${JENKINS_AGENT_ARM64_APP_BACKEND:-${DEFAULT_BACKEND}}"

CONTROLLER_TERRAFORM_DIR="${ROOT_DIR}/terraform/components/swarm/jenkins-controller/app"
EXPECTED_IMAGE_ARCH="arm64"
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

  var_args+=(-var-file "${SLICE_TFVARS}")

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
  # Image is a Renovate-visible literal in main.tf (not a variable).
  local agent_image
  agent_image="$(sed -n 's/^[[:space:]]*image[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${TERRAFORM_DIR}/main.tf" | head -1)"

  if [[ -z "${agent_image}" ]]; then
    echo "[ERR] Unable to resolve Jenkins agent image literal from ${TERRAFORM_DIR}/main.tf." >&2
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
  var_args+=(-var-file "${SLICE_TFVARS}")

  auths_json="$(printf '%s\n' 'jsonencode(coalesce(try(var.swarm_docker_provider_config.registry_auths, null), []))' | terraform -chdir="${TERRAFORM_DIR}" console "${var_args[@]}" 2>/dev/null || true)"
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

run_pre_terraform_checks() {
  if [[ ! -d "${CONTROLLER_TERRAFORM_DIR}" ]]; then
    echo "[ERR] Missing controller Terraform directory at ${CONTROLLER_TERRAFORM_DIR}. Run the controller pipeline first." >&2
    exit 1
  fi

  echo "[INFO] Checking Jenkins controller outputs"
  if ! terraform -chdir="${CONTROLLER_TERRAFORM_DIR}" init -backend-config="${BACKEND_CONFIG}" > /dev/null; then
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


usage() {
  cat <<USAGE
Usage: terraform/components/swarm/jenkins-agent-arm64/pipeline/app.sh [options] [slice_tfvars] [backend_config]

Deploy Jenkins agent arm64 (terraform init, plan, apply).

Options:
  --tfvars <path>           Slice tfvars (default: ${DEFAULT_SLICE_TFVARS})
  --backend <path>          S3 backend config (default: ${DEFAULT_BACKEND})
  -h, --help                Show this help

Environment overrides: JENKINS_AGENT_ARM64_APP_TFVARS, JENKINS_AGENT_ARM64_APP_BACKEND, CONFIG_DIR (from .config/docker/site.env)
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
require_file "backend config" "${BACKEND_CONFIG}"

echo "Terraform dir:     ${TERRAFORM_DIR}"
echo "Slice tfvars:      ${SLICE_TFVARS}"
echo "Backend config:    ${BACKEND_CONFIG}"

run_pre_terraform_checks

cd "${TERRAFORM_DIR}"

run_terraform_init() {
  local init_log
  init_log="$(mktemp -t jenkins-agent-arm64-terraform-init-XXXXXX)"

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

echo "[STEP] terraform init (Jenkins agent arm64)"
if ! run_terraform_init; then
  echo "[ERR] terraform init failed" >&2
  exit 1
fi

PLAN_ARGS=(
  -input=false
  -var-file "${SLICE_TFVARS}"
)

echo "[STEP] terraform plan (Jenkins agent arm64)"
if ! terraform plan "${PLAN_ARGS[@]}"; then
  echo "[ERR] terraform plan failed" >&2
  exit 1
fi

echo "[STEP] terraform apply (Jenkins agent arm64)"
if ! terraform apply -input=false -auto-approve "${PLAN_ARGS[@]}"; then
  echo "[ERR] terraform apply failed" >&2
  exit 1
fi

echo "[DONE] Jenkins agent arm64 apply complete."
