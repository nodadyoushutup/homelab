#!/usr/bin/env bash
# Restore production Velero nightly crons after a TEMP Kopia seed run.
# Re-checks out schedule manifests from commit 1650a9f and applies them.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROD_COMMIT="${VELERO_SCHEDULES_PROD_COMMIT:-1650a9f}"
MANIFEST_DIR="${REPO_ROOT}/kubernetes/velero/manifests"

cd "${REPO_ROOT}"

for f in "${MANIFEST_DIR}"/schedule-*.yaml; do
  rel="${f#"${REPO_ROOT}"/}"
  git show "${PROD_COMMIT}:${rel}" >"${f}"
done

echo "Restored schedule-*.yaml from ${PROD_COMMIT}"
kubectl apply --server-side --force-conflicts -f "${MANIFEST_DIR}"/schedule-*.yaml
echo "Applied production schedules to cluster."
