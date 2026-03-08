#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]:-${0}}"
SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" && pwd 2>/dev/null || pwd)"
if [[ -z "${PURGE_SCRIPT_PATH:-}" && -f "${SCRIPT_SOURCE}" && "${SCRIPT_SOURCE}" != "/bin/bash" ]]; then
  PURGE_SCRIPT_PATH="$(cd "$(dirname "${SCRIPT_SOURCE}")" && pwd)/$(basename "${SCRIPT_SOURCE}")"
fi

if ! declare -f purge_main >/dev/null 2>&1; then
  # shellcheck source=base.sh
  source "${SCRIPT_DIR}/base.sh"
fi

APP_NAME="dozzle"

purge_main "$@"
