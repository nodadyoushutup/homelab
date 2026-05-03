#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROOT_ENV_LOADER="${ROOT_DIR}/scripts/terraform/load_root_env.sh"
if [[ -f "${ROOT_ENV_LOADER}" ]]; then
  # shellcheck source=/dev/null
  source "${ROOT_ENV_LOADER}"
fi

SERVICE_NAME="vault-auto-unseal.service"
TARGET_HOST="${TARGET_HOST:-swarm-cp-0.local}"
TARGET_USER="${TARGET_USER:-${USER}}"
REMOTE_REPO_DIR="${REMOTE_REPO_DIR:-/mnt/eapp/code/homelab}"
REMOTE_TFVARS_HOME="${REMOTE_TFVARS_HOME:-${TFVARS_HOME_DIR:-${CONFIG_DIR:-/mnt/eapp/config}}}"
LOCAL_TFVARS_HOME="${LOCAL_TFVARS_HOME:-${TFVARS_HOME_DIR:-${CONFIG_DIR:-/mnt/eapp/config}}}"
SYNC_ARTIFACTS="1"

log_info() {
  echo "[INFO] $*"
}

fail() {
  echo "[ERR] $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: install_auto_unseal_service.sh [options]

Installs/updates a systemd unit on a Swarm manager that auto-unseals Vault at
boot and after Docker restarts.

Options:
  --host <host>                  Target host (default: swarm-cp-0.local)
  --user <user>                  SSH user for target host (default: current user)
  --remote-repo-dir <path>       Repo path on target host (default: /mnt/eapp/code/homelab)
  --remote-tfvars-home <path>    TFVARS home on target host (default: /mnt/eapp/config)
  --local-tfvars-home <path>     Local TFVARS home for artifact sync (default: /mnt/eapp/config)
  --no-sync-artifacts            Skip syncing vault init/env artifacts to target host
  -h, --help                     Show this help text
EOF
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || fail "Missing required command: ${cmd}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host)
        [[ $# -ge 2 ]] || fail "--host requires a value"
        TARGET_HOST="$2"
        shift 2
        ;;
      --user)
        [[ $# -ge 2 ]] || fail "--user requires a value"
        TARGET_USER="$2"
        shift 2
        ;;
      --remote-repo-dir)
        [[ $# -ge 2 ]] || fail "--remote-repo-dir requires a value"
        REMOTE_REPO_DIR="$2"
        shift 2
        ;;
      --remote-tfvars-home)
        [[ $# -ge 2 ]] || fail "--remote-tfvars-home requires a value"
        REMOTE_TFVARS_HOME="$2"
        shift 2
        ;;
      --local-tfvars-home)
        [[ $# -ge 2 ]] || fail "--local-tfvars-home requires a value"
        LOCAL_TFVARS_HOME="$2"
        shift 2
        ;;
      --no-sync-artifacts)
        SYNC_ARTIFACTS="0"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        fail "Unknown argument: $1"
        ;;
    esac
  done
}

sync_vault_artifacts() {
  local ssh_target="$1"
  local local_vault_dir remote_vault_dir
  local_vault_dir="${LOCAL_TFVARS_HOME}/vault"
  remote_vault_dir="${REMOTE_TFVARS_HOME}/vault"

  [[ -f "${local_vault_dir}/init.json" ]] || fail "Missing ${local_vault_dir}/init.json"
  [[ -f "${local_vault_dir}/.env" ]] || fail "Missing ${local_vault_dir}/.env"

  log_info "Syncing Vault bootstrap artifacts to ${ssh_target}:${remote_vault_dir}"
  ssh "${ssh_target}" "install -d -m 0750 '${remote_vault_dir}'"
  scp "${local_vault_dir}/init.json" "${ssh_target}:${remote_vault_dir}/init.json" >/dev/null
  scp "${local_vault_dir}/.env" "${ssh_target}:${remote_vault_dir}/.env" >/dev/null
  ssh "${ssh_target}" "chmod 0640 '${remote_vault_dir}/init.json' '${remote_vault_dir}/.env'"
}

install_service_unit() {
  local ssh_target="$1"
  local unit_path="/etc/systemd/system/${SERVICE_NAME}"
  local vault_unseal_script="${REMOTE_REPO_DIR}/scripts/vault/unseal.sh"

  log_info "Installing ${SERVICE_NAME} on ${ssh_target}"
  ssh "${ssh_target}" "sudo install -d -m 0755 /etc/systemd/system"
  ssh "${ssh_target}" "sudo tee '${unit_path}' >/dev/null" <<EOF
[Unit]
Description=Auto-unseal HashiCorp Vault after Docker startup
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
User=${TARGET_USER}
Environment=TFVARS_HOME_DIR=${REMOTE_TFVARS_HOME}
Environment=VAULT_SWARM_MANAGER_HOST=${TARGET_HOST}
ExecStart=/usr/bin/env bash ${vault_unseal_script}
TimeoutStartSec=240
Restart=on-failure
RestartSec=15

[Install]
WantedBy=multi-user.target
WantedBy=docker.service
EOF

  ssh "${ssh_target}" "sudo systemctl daemon-reload"
  ssh "${ssh_target}" "sudo systemctl enable '${SERVICE_NAME}' >/dev/null"
  ssh "${ssh_target}" "sudo systemctl restart '${SERVICE_NAME}'"
  ssh "${ssh_target}" "systemctl status '${SERVICE_NAME}' --no-pager -l | sed -n '1,60p'"
}

main() {
  local ssh_target

  parse_args "$@"
  require_cmd ssh
  require_cmd scp

  ssh_target="${TARGET_USER}@${TARGET_HOST}"

  if [[ "${SYNC_ARTIFACTS}" == "1" ]]; then
    sync_vault_artifacts "${ssh_target}"
  else
    log_info "Skipping Vault artifact sync (--no-sync-artifacts)."
  fi

  install_service_unit "${ssh_target}"
  log_info "Install complete."
}

main "$@"
