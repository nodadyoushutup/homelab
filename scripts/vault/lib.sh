# Shared Vault script path resolution. Source after load_root_env.sh.
# Canonical site path: <CONFIG_DIR>/terraform/components/swarm/vault/

resolve_vault_paths() {
  local root_dir="$1"
  local primary_home primary_dir canonical_init

  if [[ -n "${VAULT_INIT_FILE:-}" ]]; then
    if [[ ! -f "${VAULT_INIT_FILE}" ]]; then
      return 1
    fi
    VAULT_TFVARS_DIR="$(dirname "${VAULT_INIT_FILE}")"
    VAULT_TFVARS_HOME="$(cd "${VAULT_TFVARS_DIR}/../../.." && pwd)"
    VAULT_ENV_FILE="${VAULT_ENV_FILE:-${VAULT_TFVARS_DIR}/.env}"
    return 0
  fi

  primary_home="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${root_dir}/.config}}"
  primary_dir="${VAULT_TFVARS_DIR:-${primary_home}/terraform/components/swarm/vault}"
  canonical_init="${primary_dir}/init.json"

  VAULT_TFVARS_HOME="${primary_home}"
  VAULT_TFVARS_DIR="${primary_dir}"
  VAULT_INIT_FILE="${canonical_init}"
  VAULT_ENV_FILE="${VAULT_TFVARS_DIR}/.env"

  [[ -f "${VAULT_INIT_FILE}" ]]
}
