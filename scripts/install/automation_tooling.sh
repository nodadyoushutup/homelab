#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

is_enabled() {
  case "${1:-1}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    0|false|FALSE|no|NO|off|OFF) return 1 ;;
    *) die "Expected a boolean-like value, got '${1}'." ;;
  esac
}

run_script() {
  local script_name="$1"
  local script_path="${SCRIPT_DIR}/${script_name}"

  [[ -f "${script_path}" ]] || die "Required script not found: ${script_path}"
  chmod 0755 "${script_path}" 2>/dev/null || true

  log "Running ${script_name}"
  "${script_path}"
}

run_script_env() {
  local script_name="$1"
  shift

  local script_path="${SCRIPT_DIR}/${script_name}"
  [[ -f "${script_path}" ]] || die "Required script not found: ${script_path}"
  chmod 0755 "${script_path}" 2>/dev/null || true

  log "Running ${script_name}"
  env "$@" "${script_path}"
}

main() {
  local target_user
  target_user="${AUTOMATION_TARGET_USER:-${TARGET_USER:-}}"

  if is_enabled "${AUTOMATION_INSTALL_PACKAGES:-1}"; then
    run_script packages.sh
  fi

  if is_enabled "${AUTOMATION_INSTALL_DOCKER:-1}"; then
    run_script_env docker.sh \
      "INSTALL_DOCKER_PROFILE=${AUTOMATION_DOCKER_PROFILE:-full}" \
      "DOCKER_CONFIGURE_USER=${AUTOMATION_DOCKER_CONFIGURE_USER:-1}" \
      "DOCKER_ENABLE_SERVICE=${AUTOMATION_DOCKER_ENABLE_SERVICE:-1}" \
      "DOCKER_VERIFY=${AUTOMATION_DOCKER_VERIFY:-1}" \
      "TARGET_USER=${target_user}"
  fi

  if is_enabled "${AUTOMATION_INSTALL_TERRAFORM:-1}"; then
    run_script terraform.sh
  fi

  if is_enabled "${AUTOMATION_INSTALL_ANSIBLE:-1}"; then
    run_script ansible.sh
  fi

  if is_enabled "${AUTOMATION_INSTALL_KUBECTL:-1}"; then
    run_script kubectl.sh
  fi

  if is_enabled "${AUTOMATION_INSTALL_K9S:-1}"; then
    run_script k9s.sh
  fi

  if is_enabled "${AUTOMATION_INSTALL_PACKER:-1}"; then
    run_script_env packer.sh \
      "PACKER_CONFIGURE_USER=${AUTOMATION_PACKER_CONFIGURE_USER:-1}" \
      "TARGET_USER=${target_user}"
  fi

  if is_enabled "${AUTOMATION_INSTALL_MINIO_CLIENT:-1}"; then
    run_script minio_client.sh
  fi

  log "Shared automation tooling bundle complete."
}

main "$@"
