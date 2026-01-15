#!/usr/bin/env bash
set -e

if [[ $# -lt 1 ]]; then
  echo "Usage: scripts/pipeline/terraform_exec.sh <args...>" >&2
  exit 64
fi

FILTER_AVAILABLE="${FILTER_AVAILABLE:-0}"
PYTHON_CMD="${PYTHON_CMD:-}"
FILTER_SCRIPT="${FILTER_SCRIPT:-}"

if [[ "${FILTER_AVAILABLE}" == "1" && -n "${PYTHON_CMD}" && -n "${FILTER_SCRIPT}" && -f "${FILTER_SCRIPT}" ]]; then
  "${PYTHON_CMD}" "${FILTER_SCRIPT}" -- "$@"
else
  terraform "$@"
fi
