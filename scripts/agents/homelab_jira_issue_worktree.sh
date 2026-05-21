#!/usr/bin/env bash
# Create a Git worktree for Jira-driven agent work and print LangGraph configurable.
# Usage: ./homelab_jira_issue_worktree.sh HOME-123 [base-ref]
# Env:
#   HOMELAB_REPO_ROOT        — main checkout (default: /mnt/eapp/code/homelab)
#   HOMELAB_WORKTREE_PARENT  — parent dir for worktrees (default: /mnt/eapp/code/homelab-wt)
set -euo pipefail

JIRA_KEY="${1:?usage: $0 JIRA-123 [base-ref]}"
BASE_REF="${2:-origin/main}"
REPO="${HOMELAB_REPO_ROOT:-/mnt/eapp/code/homelab}"
PARENT="${HOMELAB_WORKTREE_PARENT:-/mnt/eapp/code/homelab-wt}"
WT_PATH="${PARENT}/${JIRA_KEY}"
BRANCH="jira/$(echo "${JIRA_KEY}" | tr '[:upper:]' '[:lower:]')"

mkdir -p "${PARENT}"

if [[ ! -d "${REPO}/.git" ]]; then
  echo "[error] not a git repo: ${REPO}" >&2
  exit 1
fi

git -C "${REPO}" fetch origin 2>/dev/null || true

if [[ -d "${WT_PATH}" ]]; then
  echo "[info] worktree already exists: ${WT_PATH}"
else
  git -C "${REPO}" worktree add -b "${BRANCH}" "${WT_PATH}" "${BASE_REF}"
  echo "[info] created worktree ${WT_PATH} branch ${BRANCH}"
fi

echo ""
echo "=== LangGraph thread configurable (JSON fragment) ==="
echo "Pass under RunnableConfig[\"configurable\"] when starting or continuing the thread:"
echo ""
cat <<EOF
{
  "homelab_code_repository_root": "${WT_PATH}"
}
EOF
echo ""
echo "=== Notes ==="
echo "- Code and Tech Lead specialists honor homelab_code_repository_root for MCP path scoping."
echo "- Use Cursor shell or local git in ${WT_PATH} for filesystem edits and commits."
