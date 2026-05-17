#!/usr/bin/env bash
# Apply committed Velero nightly schedules (midnight start, 5-minute stagger).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST_DIR="${REPO_ROOT}/kubernetes/velero/manifests"

for f in "${MANIFEST_DIR}"/schedule-*.yaml; do
  kubectl apply --server-side --force-conflicts -f "${f}"
done
echo "Applied Velero schedules from ${MANIFEST_DIR}"
