# Shared Vault script path resolution. Source after load_root_env.sh.
#
# When CONFIG_DIR points at a legacy external tree (e.g. /mnt/eapp/config) that no
# longer mirrors terraform/swarm/vault, fall back to repo .config and _old/ copies.

_vault_lib_warn() {
  echo "[WARN] $*" >&2
}

resolve_vault_paths() {
  local root_dir="$1"
  local primary_home primary_dir canonical_init
  local -a init_candidates
  local candidate

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
  primary_dir="${VAULT_TFVARS_DIR:-${primary_home}/terraform/swarm/vault}"
  canonical_init="${primary_dir}/init.json"

  init_candidates=(
    "${canonical_init}"
    "${root_dir}/.config/terraform/swarm/vault/init.json"
    "${primary_home}/_old/terraform/swarm/vault/init.json"
  )

  for candidate in "${init_candidates[@]}"; do
    if [[ -f "${candidate}" ]]; then
      VAULT_INIT_FILE="${candidate}"
      VAULT_TFVARS_DIR="$(dirname "${candidate}")"
      VAULT_TFVARS_HOME="$(cd "${VAULT_TFVARS_DIR}/../../.." && pwd)"
      VAULT_ENV_FILE="${VAULT_TFVARS_DIR}/.env"
      if [[ "${candidate}" != "${canonical_init}" ]]; then
        _vault_lib_warn "Using ${VAULT_INIT_FILE} (${canonical_init} not found; set VAULT_INIT_FILE to override)"
      fi
      return 0
    fi
  done

  VAULT_TFVARS_HOME="${primary_home}"
  VAULT_TFVARS_DIR="${primary_dir}"
  VAULT_INIT_FILE="${canonical_init}"
  VAULT_ENV_FILE="${VAULT_TFVARS_DIR}/.env"
  return 1
}
