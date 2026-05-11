# mcp-code: worktrees and multiple agents

This document is the **operating pattern** for using **mcp-code** when more than
one automated agent (or human + agent) should work on the **same GitHub
repository** at the **same time** without sharing one working directory.

## What one mcp-code process is

A running **mcp-code** container is a **single** composite MCP:

- **Filesystem** and **git** children are started with **one** directory:
  `MCP_CODE_WORKSPACE_ROOT`.
- **Ast-grep** is aligned to that same tree by default (`AST_GREP_DEFAULT_PROJECT_ROOT`
  and `AST_GREP_ALLOWED_ROOTS` default to that path unless you override them).

There is **no** per-request switch of filesystem or git root. All clients that
hit **that** process share **one** checkout.

## Why a shared URL is not isolation

If every LangGraph thread, Cursor session, or Codex run points at the **same**
HTTPS endpoint (for example `https://mcp.code.nodadyoushutup.com/mcp`) backed by
**one** Swarm service with **one** `MCP_CODE_WORKSPACE_ROOT`, then every client
is editing and committing against the **same working tree**. They **will** step on
each other (same files, same index, same uncommitted changes).

**Ast-grep, filesystem, and git are consistent with each other**, but they are
consistent on **one** tree only.

## Git worktrees (the Git-side pattern)

**Worktrees** give you **multiple working directories** attached to the **same**
`.git` object database, each able to check out a **different branch**.

Typical layout on a shared code mount (example paths):

- Main checkout: `/mnt/eapp/code/homelab`
- Agent A: `/mnt/eapp/code/homelab-wt/agent-a-feature`
- Agent B: `/mnt/eapp/code/homelab-wt/agent-b-fix`

Create a worktree (run on a host that has the repo; adjust branch and path):

```bash
git -C /mnt/eapp/code/homelab fetch origin
git -C /mnt/eapp/code/homelab worktree add ../homelab-wt/my-task origin/main
# then create/switch branch inside that worktree as usual
```

Worktrees are normal directories; NFS or bind mounts can expose them to Swarm
nodes the same way you expose `/mnt/eapp/code`.

## Isolation pattern: one MCP backend per worktree

To keep agents independent:

1. **Pick one worktree directory per concurrent “lane”** (per agent session,
   per ticket, or per long-running branch).
2. Run **mcp-code** with **`MCP_CODE_WORKSPACE_ROOT` set to that directory**
   (and leave ast-grep defaults unless you have a reason to widen
   `AST_GREP_ALLOWED_ROOTS`).
3. Give **each lane its own MCP URL** that reaches **that** backend only.

Concretely, that usually means **multiple Swarm services** (or tasks) from the
same image, different service names, different published port or hostname, and
different env — not one global URL for all concurrent writers.

## LangGraph: per-thread mcp-code URL and worktree path

The Homelab LangGraph app applies **`RunnableConfig["configurable"]`** on every
tool call (Code, Git, and Tech Lead specialists):

| Key | Purpose |
| --- | --- |
| `homelab_mcp_code_url` | HTTPS URL of the **mcp-code** service whose `MCP_CODE_WORKSPACE_ROOT` is this thread’s worktree. |
| `homelab_code_repository_root` | Absolute path to that same directory (used to normalize filesystem / ast-grep paths in the agent). |

If these keys are **omitted**, behavior falls back to **`HOMELAB_MCP_CODE_URL`**
(in `mcp.json` / env) and the agent’s default repo root (`HOMELAB_REPO_ROOT` /
`CODE_REPOSITORY_ROOT` / `TECH_LEAD_REPOSITORY_ROOT` as today).

**Thread isolation:** each concurrent Jira (or feature) lane should use its **own**
LangGraph thread with its **own** `configurable` pair, plus its **own** mcp-code
backend mounted at `homelab_code_repository_root`.

## Jira-led implementation: commit, push, PR (human in the loop)

Default delivery path for “implement this ticket” work:

1. **Provision** a Git **worktree** and matching **mcp-code** deployment (or reuse
   a pre-defined “lane”) so the filesystem + local git MCP see only that tree.
2. **Start** the LangGraph thread with `homelab_mcp_code_url` and
   `homelab_code_repository_root` set to that lane (see script below).
3. **Supervisor flow:** `jira` (issue context) → `code` (reads/edits + **local git**
   commit/push via mcp-code) → `github` (open/update **pull request**, checks).
   Prefer a **draft** PR when the operator wants an early checkpoint.
4. **Do not** merge to the default branch from the agent. The human reviews the PR,
   requests changes, or merges when satisfied (see `docs/subagents/github/02-pull-requests.md`).

Helper (prints a configurable JSON fragment):

- `scripts/agents/homelab_jira_issue_worktree.sh`

## Same lane: local git + filesystem together

For a single task, **local-git** and **filesystem** tools should target the **same**
tree. **mcp-code** bundles both under one endpoint; **one URL per worktree** keeps
**status/commit** and **file edits** on the same checkout.

## Summary

| Goal | Pattern |
| --- | --- |
| Multiple agents, no collisions | **Separate** `MCP_CODE_WORKSPACE_ROOT` per agent lane (worktree path), **separate** MCP endpoint per lane. |
| One shared URL for everyone | **Single** shared working tree — fine for **read-mostly** or **one writer**; **not** safe for parallel independent edits. |
| Branch isolation | **Git worktrees** (different dirs); **not** only different branch names in one dir. |

## Related

- Application build and env table: `applications/mcp-code/README.md`
- Swarm deploy: `terraform/swarm/mcp-code/app/` (duplicate stacks or services per lane as needed)
- LangGraph routing implementation: `applications/langgraph/framework/mcp_workspace_context.py`
- Code subagent: generic prompt
  `applications/langgraph/framework/agents/system_prompts/code_system_prompt.md`;
  homelab runtime overlays `docs/subagents/code/01-runtime.md` et al.
- GitHub subagent: `docs/subagents/github/01-runtime.md`
