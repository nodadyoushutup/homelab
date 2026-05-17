#!/usr/bin/env bash
# Remove Failed/PartiallyFailed Velero backups superseded by a newer run for the same
# schedule (plus failed manual backups). Uses `velero backup delete` so data is removed
# from the BSL; kubectl delete alone causes the backup sync controller to re-import them.
#
# Usage:
#   scripts/misc/velero_prune_legacy_backups.sh          # dry-run
#   scripts/misc/velero_prune_legacy_backups.sh --apply   # delete

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VELERO_NAMESPACE="${VELERO_NAMESPACE:-velero}"
VELERO_IMAGE="${VELERO_IMAGE:-docker.io/velero/velero:v1.18.0}"
APPLY=0

if [[ "${1:-}" == "--apply" ]]; then
  APPLY=1
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $(basename "$0") [--apply]" >&2
  exit 1
fi

mapfile -t DELETE_NAMES < <(
  kubectl get backup -n "${VELERO_NAMESPACE}" -o json | python3 -c "
import json, sys
from collections import defaultdict

items = json.load(sys.stdin).get('items', [])
by_sched = defaultdict(list)
for b in items:
    sched = b.get('metadata', {}).get('labels', {}).get('velero.io/schedule-name')
    if sched:
        by_sched[sched].append(b)

def newer_exists(b):
    name = b['metadata']['name']
    sched = b.get('metadata', {}).get('labels', {}).get('velero.io/schedule-name')
    if not sched:
        return True
    return any(s['metadata']['name'] > name for s in by_sched[sched])

for b in items:
    phase = b.get('status', {}).get('phase', '')
    if phase in ('Failed', 'PartiallyFailed') and newer_exists(b):
        print(b['metadata']['name'])
"
)

if [[ ${#DELETE_NAMES[@]} -eq 0 ]]; then
  echo "No superseded Failed/PartiallyFailed backups to prune."
  exit 0
fi

echo "Backups to delete (${#DELETE_NAMES[@]}):"
for n in "${DELETE_NAMES[@]}"; do
  phase=$(kubectl get backup -n "${VELERO_NAMESPACE}" "${n}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "?")
  echo "  ${n} (${phase})"
done

if [[ "${APPLY}" -eq 0 ]]; then
  echo ""
  echo "Dry-run only. Re-run with --apply to delete (cluster + object storage)."
  exit 0
fi

echo ""
ARGS=""
for n in "${DELETE_NAMES[@]}"; do
  ARGS+=" $(printf '%q' "${n}")"
done

kubectl -n "${VELERO_NAMESPACE}" run velero-prune-legacy --rm -i --restart=Never \
  --image="${VELERO_IMAGE}" \
  --overrides='{"spec":{"serviceAccountName":"velero-server"}}' \
  -- /velero backup delete --confirm${ARGS}

echo "Delete submitted. Velero will remove BSL data in the background."
