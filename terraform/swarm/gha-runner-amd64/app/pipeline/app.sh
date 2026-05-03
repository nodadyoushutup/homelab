#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
exec "${ROOT_DIR}/pipelines/terraform/swarm/gha-runner-amd64/app.sh" "$@"
