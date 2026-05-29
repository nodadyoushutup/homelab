#!/usr/bin/env bash
# Test Zot registry login using credentials from components tfvars.
#
# Usage: scripts/zot/auth_test.sh [--registry-tfvars PATH] [--address HOST]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REGISTRY_TFVARS="${ZOT_REGISTRY_TFVARS:-${ROOT_DIR}/.config/terraform/components/swarm.tfvars}"
REGISTRY_ADDRESS="${ZOT_REGISTRY_ADDRESS:-zot.nodadyoushutup.com}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry-tfvars)
      REGISTRY_TFVARS="$2"
      shift 2
      ;;
    --address)
      REGISTRY_ADDRESS="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: scripts/zot/auth_test.sh [--registry-tfvars PATH] [--address HOST]"
      exit 0
      ;;
    *)
      echo "[ERR] Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

[[ -f "${REGISTRY_TFVARS}" ]] || {
  echo "[ERR] Missing tfvars: ${REGISTRY_TFVARS}" >&2
  exit 1
}

readarray -t creds < <(
  python3 - "${REGISTRY_TFVARS}" "${REGISTRY_ADDRESS}" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
address = sys.argv[2]
for block in re.findall(r"\{[^{}]*\}", text, flags=re.DOTALL):
    if f'address  = "{address}"' not in block and f'address = "{address}"' not in block:
        continue
    user = re.search(r'username\s*=\s*"([^"]+)"', block)
    pw = re.search(r'password\s*=\s*"([^"]+)"', block)
    if user and pw:
        print(user.group(1))
        print(pw.group(1))
        break
else:
    raise SystemExit(f"[ERR] No registry_auths for {address!r} in {sys.argv[1]}")
PY
)

username="${creds[0]}"
password="${creds[1]}"

echo "[STEP] docker login ${REGISTRY_ADDRESS} (user ${username})"
if ! echo "${password}" | docker login "${REGISTRY_ADDRESS}" -u "${username}" --password-stdin; then
  echo "[ERR] docker login failed" >&2
  exit 1
fi

echo "[STEP] GET /v2/"
code="$(curl -s -o /dev/null -w '%{http_code}' -u "${username}:${password}" "https://${REGISTRY_ADDRESS}/v2/")"
echo "[INFO] /v2/ HTTP ${code}"
if [[ "${code}" != "200" && "${code}" != "401" ]]; then
  echo "[WARN] Expected 200 (or 401 without catalog); check NPM / Zot service." >&2
fi

echo "[DONE] Login succeeded"
