#!/usr/bin/env bash
# Stage all changes in the homelab repo, commit, and push.
# Optional first argument overrides the commit message (default: "Auto Commit").
# Skips the commit step when there is nothing staged (avoids empty commits).

set -euo pipefail

log() {
  printf '[auto-commit] %s\n' "$*"
}

COMMIT_MESSAGE="${1:-Auto Commit}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "error: not a git repository: $REPO_ROOT"
  exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
UPSTREAM="$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || true)"
log "repo: $REPO_ROOT"
log "branch: $BRANCH"
if [[ -n "$UPSTREAM" ]]; then
  log "upstream: $UPSTREAM"
else
  log "upstream: (not set — push may fail until you set tracking)"
fi
log "commit message: $COMMIT_MESSAGE"
log "status before add:"
git status -sb | sed 's/^/[auto-commit]   /'

log "running: git add -A"
git add -A

if git diff --staged --quiet; then
  log "nothing staged — skipping commit (tree clean after add)"
else
  log "staged changes:"
  git diff --staged --stat | sed 's/^/[auto-commit]   /'
  log "running: git commit -m <message>"
  git commit -m "$COMMIT_MESSAGE"
  log "commit created: $(git rev-parse --short HEAD)"
fi

log "running: git push"
git push
log "push finished"
