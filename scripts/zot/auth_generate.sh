#!/usr/bin/env bash
# Generate a Zot-compatible htpasswd file (bcrypt) for bind-mount auth.
#
# Usage: scripts/zot/auth_generate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEFAULT_OUTPUT="${ROOT_DIR}/.config/terraform/swarm/zot/htpasswd"
DEFAULT_USERNAME="homelab"

usage() {
  cat <<'EOF'
Usage: scripts/zot/auth_generate.sh

Prompts for registry username and password, then writes a bcrypt htpasswd file.
Default output: .config/terraform/swarm/zot/htpasswd

Username/password must match registry_auths for zot.nodadyoushutup.com in
.config/terraform/components/swarm/swarm.tfvars and
.config/terraform/components/runners/{amd64,arm64}.tfvars.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 0 ]]; then
  echo "[ERR] Unknown argument: $1 (use --help)" >&2
  exit 2
fi

generate_htpasswd_line() {
  local user="$1"
  local pass="$2"

  if command -v htpasswd >/dev/null 2>&1; then
    htpasswd -nBb "${user}" "${pass}"
    return 0
  fi

  if command -v python3 >/dev/null 2>&1 && python3 -c "import bcrypt" >/dev/null 2>&1; then
    python3 - "${user}" "${pass}" <<'PY'
import bcrypt
import sys

user, password = sys.argv[1], sys.argv[2]
hashed = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt(rounds=10))
line = hashed.decode("utf-8")
if line.startswith("$2b$"):
    line = "$2y$" + line[4:]
print(f"{user}:{line}", end="")
PY
    return 0
  fi

  if command -v docker >/dev/null 2>&1; then
    docker run --rm --entrypoint htpasswd httpd:2-alpine -nBb "${user}" "${pass}" 2>/dev/null \
      | tr -d '\r'
    return 0
  fi

  echo "[ERR] Need htpasswd (apache2-utils), python3 with bcrypt, or docker." >&2
  return 1
}

read -r -p "Username [${DEFAULT_USERNAME}]: " username
username="${username:-${DEFAULT_USERNAME}}"
if [[ -z "${username}" ]]; then
  echo "[ERR] Username is required." >&2
  exit 1
fi

password=""
while [[ -z "${password}" ]]; do
  read -r -s -p "Password: " password
  echo
  if [[ -z "${password}" ]]; then
    echo "[ERR] Password is required." >&2
  fi
done

read -r -s -p "Confirm password: " password_confirm
echo
if [[ "${password}" != "${password_confirm}" ]]; then
  echo "[ERR] Passwords do not match." >&2
  exit 1
fi

read -r -p "Output path [${DEFAULT_OUTPUT}]: " output_path
output_path="${output_path:-${DEFAULT_OUTPUT}}"

if [[ -e "${output_path}" && ! -f "${output_path}" ]]; then
  echo "[ERR] Output path exists and is not a file: ${output_path}" >&2
  exit 1
fi

if [[ -f "${output_path}" ]]; then
  read -r -p "File exists. Overwrite? [y/N]: " overwrite
  if [[ ! "${overwrite}" =~ ^[Yy]$ ]]; then
    echo "[INFO] Aborted."
    exit 0
  fi
fi

output_dir="$(dirname "${output_path}")"
mkdir -p "${output_dir}"

line="$(generate_htpasswd_line "${username}" "${password}")"
printf '%s\n' "${line}" >"${output_path}"
chmod 644 "${output_path}"

echo "[DONE] Wrote ${output_path} for user ${username}"
echo "[INFO] Re-run terraform plan/apply (or terraform/swarm/zot/pipeline/app.sh) on a host that sees this file at htpasswd_path."
