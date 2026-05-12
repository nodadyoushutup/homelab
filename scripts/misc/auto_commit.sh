#!/usr/bin/env bash
# Stage all changes in the homelab repo, commit with a fixed message, and push.
# Skips the commit step when there is nothing staged (avoids empty commits).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: not a git repository: $REPO_ROOT" >&2
  exit 1
fi

git add -A

if git diff --staged --quiet; then
  echo "Nothing to commit; working tree clean after staging."
else
  git commit -m "Auto Commit"
fi

git push
