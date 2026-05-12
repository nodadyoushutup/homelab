#!/usr/bin/env bash
set -euo pipefail

# Squash all commits on the current branch into a single new commit,
# then force-push that single commit to the same branch on origin.
#
# Usage:
#   ./squash-history.sh
#   ./squash-history.sh "Initial commit"
#
# WARNING:
# This rewrites Git history and force-pushes to origin.
# Existing clones will need to re-clone or reset.

COMMIT_MESSAGE="${1:-Initial commit}"
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
TEMP_BRANCH="new-${CURRENT_BRANCH}-$(date +%s)"

if [[ "$CURRENT_BRANCH" == "HEAD" ]]; then
  echo "Error: You are in detached HEAD state. Checkout a branch first."
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: Working tree is not clean. Commit, stash, or discard changes first."
  exit 1
fi

echo "Current branch: $CURRENT_BRANCH"
echo "Temporary orphan branch: $TEMP_BRANCH"
echo "New commit message: $COMMIT_MESSAGE"
echo

read -r -p "This will rewrite history and force-push to origin/$CURRENT_BRANCH. Continue? [y/N] " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

echo "Creating orphan branch: $TEMP_BRANCH"
git checkout --orphan "$TEMP_BRANCH"

echo "Adding all files..."
git add -A

echo "Creating single commit..."
git commit -m "$COMMIT_MESSAGE"

echo "Force-pushing $TEMP_BRANCH to origin/$CURRENT_BRANCH"
git push origin "$TEMP_BRANCH:$CURRENT_BRANCH" --force

echo "Checking out $CURRENT_BRANCH locally..."
git checkout "$CURRENT_BRANCH"

echo "Resetting local $CURRENT_BRANCH to $TEMP_BRANCH"
git reset --hard "$TEMP_BRANCH"

echo "Deleting temporary local branch: $TEMP_BRANCH"
git branch -D "$TEMP_BRANCH"

echo
echo "Done. origin/$CURRENT_BRANCH now has a single-commit history."
echo "Reminder: old tags, other branches, forks, PR refs, and existing clones may still retain old commits."