#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
FILTER_SCRIPT_PATH="${SCRIPT_DIR}/terraform_output_filter.py"

command -v terraform >/dev/null 2>&1 || { echo "[ERR] terraform not found in PATH" >&2; exit 127; }
command -v realpath  >/dev/null 2>&1 || { echo "[ERR] realpath not found in PATH" >&2; exit 127; }

PYTHON_CMD=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON_CMD="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
  PYTHON_CMD="$(command -v python)"
fi

if [[ -z "${PYTHON_CMD}" ]]; then
  echo "[WARN] python3 not found; Terraform warnings will be displayed" >&2
fi

FILTER_AVAILABLE=0
FILTER_SCRIPT=""
if [[ -n "${PYTHON_CMD}" && -f "${FILTER_SCRIPT_PATH}" ]]; then
  FILTER_AVAILABLE=1
  FILTER_SCRIPT="$(realpath "${FILTER_SCRIPT_PATH}")"
elif [[ -n "${PYTHON_CMD}" ]]; then
  echo "[WARN] Terraform filter helper missing at ${FILTER_SCRIPT_PATH}; warnings will be displayed" >&2
fi

echo "PYTHON_CMD=${PYTHON_CMD}"
echo "FILTER_SCRIPT=${FILTER_SCRIPT}"
echo "FILTER_AVAILABLE=${FILTER_AVAILABLE}"
echo "SCRIPT_ROOT=${SCRIPT_DIR}"
