# Code Repo Discovery (homelab)

Generic discovery order and analysis discipline are in the framework **Generic Code
Agent** system prompt. Use this file for **this repository’s** orientation.

## Where to look first

- The **supervisor** runs two **`rag_search`** calls before delegating repository
  work to you: first for `docs/subagents/code/` plus relevant workflow guidance,
  then for likely code/configuration locations. Use paths and doc anchors from
  the task as your starting map. Run **`rag_search` again** only when you still
  need index-level narrowing.
- **`AGENTS.md`** at the repo root indexes workflow and documentation sources of
  truth; consult it when you need ownership, deployment boundaries, or local
  conventions.
- **`docs/workflows/`** holds repeatable execution workflows (Docker publish,
  edge DNS, MCP worktrees, LangGraph, etc.).

## Search scope in this repo

- Prefer narrow targeted searches. Example subtrees that often narrow the problem:
  `applications/`, `docs/`, `kubernetes/`, `terraform/`, `scripts/`,
  `docker/`.
