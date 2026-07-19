#!/usr/bin/env bash
# Shared loader for the homelab-config-managed Packer build defaults.
#
# Parses the operator's .config/packer/build.pkrvars.hcl (rendered by the
# homelab-config web app) and exposes each scalar setting as a PKRCFG_<key>
# shell variable. Callers seed their own default variables from these BEFORE
# parsing CLI flags, so explicit flags still override the managed defaults.
#
# The file is shaped like a Packer var-file but also carries orchestration keys
# (distro, build_arch, target, publish) that are NOT Packer variables, so we
# parse it here for defaults instead of feeding it to `packer -var-file`.

# Known scalar keys we accept from the config file (ignore anything else).
_PACKER_CONFIG_KEYS=(
  distro
  image_version
  gui
  install_node_exporter
  ubuntu_release
  centos_stream
  arch_snapshot
  kali_release
  target
  build_arch
  amd64_accelerator
  arm64_accelerator
  publish
)

# packer_config_load [config_file]
#
# Reads the given build.pkrvars.hcl (default: ${CONFIG_DIR:-<repo>/.config}/packer/
# build.pkrvars.hcl) and sets PKRCFG_<key> for each recognized key present. Keys
# absent from the file are left unset. Missing file is a no-op (silent).
packer_config_load() {
  local script_dir repo_root config_dir config_file
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd -- "${script_dir}/../.." && pwd)"
  config_dir="${CONFIG_DIR:-${repo_root}/.config}"
  config_file="${1:-${config_dir}/packer/build.pkrvars.hcl}"

  [[ -f "${config_file}" ]] || return 0

  local line key value
  while IFS= read -r line || [[ -n "${line}" ]]; do
    # Strip inline/whole-line comments and surrounding whitespace.
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "${line}" ]] && continue
    [[ "${line}" == *"="* ]] || continue

    key="${line%%=*}"
    value="${line#*=}"
    # Trim whitespace around key and value.
    key="${key%"${key##*[![:space:]]}"}"
    key="${key#"${key%%[![:space:]]*}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    # Only accept known keys.
    local known=0 k
    for k in "${_PACKER_CONFIG_KEYS[@]}"; do
      [[ "${key}" == "${k}" ]] && known=1 && break
    done
    [[ "${known}" -eq 1 ]] || continue

    # Strip a single surrounding pair of double quotes for string values.
    if [[ "${value}" == \"*\" ]]; then
      value="${value#\"}"
      value="${value%\"}"
    fi

    printf -v "PKRCFG_${key}" '%s' "${value}"
  done <"${config_file}"
}
