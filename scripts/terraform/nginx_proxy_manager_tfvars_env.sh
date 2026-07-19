#!/usr/bin/env bash
# Export path to the Nginx Proxy Manager provider credentials tfvars
# (config-id: terraform/providers/nginx_proxy_manager). Managed by the
# homelab-config web app; the NPM config slice pipeline passes it as an extra
# -var-file alongside its own slice tfvars so the provider gets its login.
set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=resolve_config_by_id.sh
source "${_script_dir}/resolve_config_by_id.sh"

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
NGINX_PROXY_MANAGER_TFVARS="${NGINX_PROXY_MANAGER_TFVARS:-$(homelab_resolve_config_path "${TFVARS_HOME_DIR}" "terraform/providers/nginx_proxy_manager")}"
export NGINX_PROXY_MANAGER_TFVARS
