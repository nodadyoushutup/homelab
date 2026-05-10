# Repository git policies

Policies for the **Git** specialist when using the **Git MCP** against the
homelab repository. Adjust only when the user explicitly overrides them.

## Baseline hygiene

1. **Inspect before mutating:** Use status/diff/log-style tools as appropriate
   before creating branches, committing, or pushing. Do not assume a clean tree.
2. **Sync before branch work:** When starting work that should be based on the
   latest shared history:
   - `fetch` from the relevant remote(s).
   - On the **integration branch** (usually `main` or the team’s default), use
     **`merge` or `pull` per team convention** so the starting point is current.
   - Prefer **rebase vs merge** only if the user or repo docs require it;
     default to **merge-based `pull`** when unsure to avoid rewriting public
     history.
3. **Never rewrite protected history** unless the user explicitly orders it and
   understands the blast radius: no `--force` push to `main` / release branches.

## Jira-driven development branches

When implementation is tied to a **Jira issue key** (e.g. `HOME-123`):

1. **Branch name:** Create a dedicated branch whose **first segment is the
   issue key**:
   - Preferred: `HOME-123` (short, matches ticket).
   - Optional suffix when the repo uses descriptive branches:
     `HOME-123-add-rag-gate` (slug in lowercase, hyphens).
2. **Starting point:** Branch from the **current default integration branch**
   after fetch + pull (or equivalent) so the branch is not based on stale SHAs.
3. **Checkout:** Switch to the new branch before implementation handoff to
   `code`.
4. **Publish:** **Push the branch** to `origin` (or the configured remote) so
   CI and reviewers can see it. Use the same branch name locally and remotely.
5. **Single issue per branch:** Avoid mixing unrelated tickets on one branch;
   split work when scopes diverge.

If the issue key is **missing** but the user describes Jira-driven work, ask the
supervisor or user for the key before naming the branch.

## Commits

- **Commit when** the user asks for commits, or when completing a logical unit
  of work they own in git (coordinate with `code` for the actual file changes
  first when edits are involved).
- **Messages:** Prefer Conventional Commits or the project’s existing style;
  **include the issue key** in the subject or body when work is ticketed (e.g.
  `HOME-123: short description`).
- **Many small commits vs one:** Prefer small commits that are easy to review;
  squash only when the user requests or when preparing a PR for a noisy WIP
  branch.

## Remotes and forks

- **Same-repo workflow (default):** Branch on the canonical repo; push to
   `origin`; open PR on GitHub. This is not a “GitHub fork” in the platform
   sense unless the user says they use forks.
- **Fork workflow:** If the user works from a personal fork, push there and open
  PR against the upstream default branch per their convention.

## Conflicts and recovery

- If **pull** or **merge** reports conflicts: report clearly, list conflicted
  paths if known, and recommend **`code`** for resolution unless the Git MCP can
  surface enough context to proceed safely.
- Do not **force-push** to shared branches. For feature branches, force-with-lease
  only if the user explicitly requests recovery from a mistaken push.

## Coordination with `code`

Typical sequence for “implement HOME-123”:

1. `jira` (optional) — fetch issue context.
2. `git` — fetch, update base, create branch `HOME-123`, push, checkout.
3. `code` — implement with RAG preflight per supervisor gates.
4. `git` — commit (if requested), push, open/update PR (see GitHub policies).
5. `jira` — transition or comment when the team workflow requires it.
