# GitHub pull requests (homelab)

Generic PR principles are in **`github_system_prompt.md`**. This file is **homelab**
policy detail.

1. **Read before write:** open PRs, diffs, checks, review state before mutating.
2. **Least privilege:** no merge, delete branch, or dismiss reviews unless the user
   asked for that outcome.
3. **Traceability:** PR **title or description** references the **Jira issue key**
   when ticketed (e.g. `HOME-123`), matching **`docs/subagents/code/14-local-git.md`**
   branch naming.

## Opening and updating

- **Base branch:** repository primary integration branch (`main` or team default)
  unless overridden.
- **Draft vs ready:** draft for WIP or expected red checks; ready when the user
  asks and checks are acceptable.
- **Description:** purpose, scope, testing notes, linked key; no secrets.

## Checks and automation

- Read workflow/check status before claiming mergeable.
- Re-run failed workflows only when tools support it; otherwise describe failure.

## Merge

- Squash or merge per project convention; do not merge on failing **required**
  checks unless the user explicitly accepts the exception.

## After merge

- Suggest remote branch cleanup when desired.
- Suggest **`jira`** when ticket columns should move after merge.
