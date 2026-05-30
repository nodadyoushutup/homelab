#!/usr/bin/env bash
# Create prometheus@pve (PVEAuditor) + API token for prometheus-pve-exporter; refresh app.tfvars env block.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/terraform/load_root_env.sh"

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
PVE_EXPORTER_TFVARS="${TFVARS_HOME_DIR}/terraform/components/swarm/prometheus-pve-exporter/app.tfvars"
CLUSTER_PROXMOX_TFVARS="${TFVARS_HOME_DIR}/terraform/components/cluster/proxmox/app.tfvars"

PVE_ENDPOINT="${PVE_ENDPOINT:-}"
PVE_MONITOR_USER="${PVE_MONITOR_USER:-prometheus@pve}"
PVE_TOKEN_ID="${PVE_TOKEN_ID:-monitoring}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--endpoint URL] [--tfvars PATH] [--cluster-tfvars PATH]

Ensures ${PVE_MONITOR_USER} exists with PVEAuditor on /, creates API token ${PVE_TOKEN_ID},
and writes PVE_* env entries into prometheus-pve-exporter app.tfvars.

Admin credentials: PROXMOX_ADMIN_USER + PROXMOX_ADMIN_PASSWORD, or parsed from cluster proxmox app.tfvars.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --endpoint)
      PVE_ENDPOINT="$2"
      shift 2
      ;;
    --tfvars)
      PVE_EXPORTER_TFVARS="$2"
      shift 2
      ;;
    --cluster-tfvars)
      CLUSTER_PROXMOX_TFVARS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERR] Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

read_proxmox_tfvars_field() {
  local field="$1"
  python3 - "${CLUSTER_PROXMOX_TFVARS}" "${field}" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
field = sys.argv[2]
m = re.search(rf'{re.escape(field)}\s*=\s*"([^"]*)"', text)
print(m.group(1) if m else "")
PY
}

if [[ -z "${PROXMOX_ADMIN_USER:-}" || -z "${PROXMOX_ADMIN_PASSWORD:-}" ]]; then
  if [[ ! -f "${CLUSTER_PROXMOX_TFVARS}" ]]; then
    echo "[ERR] Set PROXMOX_ADMIN_USER and PROXMOX_ADMIN_PASSWORD, or provide ${CLUSTER_PROXMOX_TFVARS}" >&2
    exit 1
  fi
  PROXMOX_ADMIN_USER="${PROXMOX_ADMIN_USER:-$(read_proxmox_tfvars_field username)}"
  PROXMOX_ADMIN_PASSWORD="${PROXMOX_ADMIN_PASSWORD:-$(read_proxmox_tfvars_field password)}"
fi

if [[ -z "${PVE_ENDPOINT}" && -f "${CLUSTER_PROXMOX_TFVARS}" ]]; then
  PVE_ENDPOINT="$(read_proxmox_tfvars_field endpoint)"
fi
PVE_ENDPOINT="${PVE_ENDPOINT:-https://192.168.1.10:8006}"

if [[ -z "${PROXMOX_ADMIN_USER}" || -z "${PROXMOX_ADMIN_PASSWORD}" ]]; then
  echo "[ERR] Could not resolve Proxmox admin credentials" >&2
  exit 1
fi

API_BASE="${PVE_ENDPOINT%/}/api2/json"

pve_curl() {
  local method="$1"
  local path="$2"
  shift 2
  curl -sk -X "${method}" \
    -H "Cookie: PVEAuthCookie=${PVE_TICKET}" \
    -H "CSRFPreventionToken: ${PVE_CSRF}" \
    "$@" \
    "${API_BASE}${path}"
}

echo "[INFO] Authenticating to ${PVE_ENDPOINT} as ${PROXMOX_ADMIN_USER}"
ticket_json="$(curl -sk -d "username=${PROXMOX_ADMIN_USER}&password=${PROXMOX_ADMIN_PASSWORD}" \
  "${API_BASE}/access/ticket")"
PVE_TICKET="$(printf '%s' "${ticket_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["ticket"])')"
PVE_CSRF="$(printf '%s' "${ticket_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["CSRFPreventionToken"])')"

userid_enc="${PVE_MONITOR_USER//@/%40}"

user_exists="$(pve_curl GET "/access/users/${userid_enc}" | python3 -c 'import json,sys; print(1 if json.load(sys.stdin).get("data") else 0)' 2>/dev/null || echo 0)"
if [[ "${user_exists}" != "1" ]]; then
  echo "[INFO] Creating user ${PVE_MONITOR_USER}"
  pve_curl POST "/access/users" \
    -d "userid=${PVE_MONITOR_USER}" \
    -d "enable=1" \
    -d "comment=Prometheus PVE exporter (PVEAuditor)" >/dev/null
fi

echo "[INFO] Ensuring PVEAuditor ACL on / for ${PVE_MONITOR_USER}"
pve_curl PUT "/access/acl" \
  -d "path=/" \
  -d "roles=PVEAuditor" \
  -d "users=${PVE_MONITOR_USER}" >/dev/null

token_full_id="${PVE_MONITOR_USER}!${PVE_TOKEN_ID}"
token_full_enc="${token_full_id//@/%40}"
token_full_enc="${token_full_enc//!/%21}"

if pve_curl GET "/access/users/${userid_enc}/token/${PVE_TOKEN_ID}" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("data") else 1)' 2>/dev/null; then
  echo "[INFO] Removing existing token ${PVE_MONITOR_USER}!${PVE_TOKEN_ID} (secret cannot be re-read)"
  pve_curl DELETE "/access/users/${userid_enc}/token/${PVE_TOKEN_ID}" >/dev/null
fi

echo "[INFO] Creating API token ${PVE_MONITOR_USER}!${PVE_TOKEN_ID}"
token_json="$(pve_curl POST "/access/users/${userid_enc}/token/${PVE_TOKEN_ID}" \
  -d "privsep=1" \
  -d "expire=0" \
  -d "comment=prometheus-pve-exporter")"
PVE_TOKEN_VALUE="$(printf '%s' "${token_json}" | python3 -c 'import json,sys; d=json.load(sys.stdin).get("data") or {}; print(d.get("value",""))')"

if [[ -z "${PVE_TOKEN_VALUE}" ]]; then
  echo "[ERR] Token creation failed: ${token_json}" >&2
  exit 1
fi

echo "[INFO] Ensuring PVEAuditor ACL on / for token ${token_full_id} (privsep)"
pve_curl PUT "/access/acl" \
  -d "path=/" \
  -d "roles=PVEAuditor" \
  -d "tokens=${token_full_id}" >/dev/null

mkdir -p "$(dirname "${PVE_EXPORTER_TFVARS}")"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
python3 - "${ROOT_DIR}" "${PVE_EXPORTER_TFVARS}" "${PVE_MONITOR_USER}" "${PVE_TOKEN_ID}" "${PVE_TOKEN_VALUE}" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
path = pathlib.Path(sys.argv[2])
user, token_name, token_value = sys.argv[3:6]

sys.path.insert(0, str(root / "scripts" / "terraform"))
from migrate_swarm_placement_tfvars import migrate_tfvars_text  # noqa: E402

env_block = f'''env = {{
  PVE_USER        = "{user}"
  PVE_TOKEN_NAME  = "{token_name}"
  PVE_TOKEN_VALUE = "{token_value}"
}}
'''

default_header = """# Managed by scripts/swarm/ensure_pve_prometheus_api_token.sh

placement = {
  constraints = ["node.labels.role==swarm-wk-0"]
  platforms = [
    {
      os           = "linux"
      architecture = "aarch64"
    },
  ]
}
endpoint_host            = "192.168.1.121"
published_port           = 9221
pve_targets              = ["192.168.1.10"]
verify_ssl               = false
disable_config_collector = true

"""

if path.exists():
    text = path.read_text(encoding="utf-8")
    text, _ = migrate_tfvars_text(text)
    if re.search(r"^\s*env\s*=", text, flags=re.M):
        text = re.sub(r"^\s*env\s*=\s*\{.*?\n\}\s*\n", env_block + "\n", text, count=1, flags=re.S | re.M)
    else:
        text = text.rstrip() + "\n\n" + env_block
else:
    text = default_header + env_block

path.write_text(text, encoding="utf-8")
print(f"[OK] Updated {path}")
PY

echo "[OK] Token written to ${PVE_EXPORTER_TFVARS}"
