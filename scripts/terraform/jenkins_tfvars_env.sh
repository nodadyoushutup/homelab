#!/usr/bin/env bash
# Export path to the Jenkins provider credentials tfvars
# (config-id: terraform/providers/jenkins). Managed by the homelab-config web
# app; the Jenkins controller config slice pipeline passes it as an extra
# -var-file alongside its own slice tfvars so the provider gets its login.
set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=resolve_config_by_id.sh
source "${_script_dir}/resolve_config_by_id.sh"

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
JENKINS_TFVARS="${JENKINS_TFVARS:-$(homelab_resolve_config_path "${TFVARS_HOME_DIR}" "terraform/providers/jenkins")}"
export JENKINS_TFVARS
