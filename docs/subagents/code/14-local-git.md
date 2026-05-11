# Local git (homelab overlay)

Generic local-git and GitHub handoff rules are in the framework **Generic Code
Agent** system prompt (**Local repository and Git** and **Tool use and search**).

## Policies for this repository

1. **Inspect before mutating:** status/diff/log-style tools before branch, commit, or
   push. Do not assume a clean tree.
2. **Sync before branch work:** fetch; on the integration branch (usually `main`),
   merge or pull per team convention so the starting point is current. Prefer
   merge-based `pull` when unsure.
3. **Never rewrite protected history** without explicit caller approval: no
   `--force` push to `main` / release branches.

## Jira-driven branches (`HOME`)

When work ties to a **Jira issue key** (e.g. `HOME-123`):

1. **Branch name:** first segment is the issue key — `HOME-123` or
   `HOME-123-short-slug` (lowercase, hyphens).
2. **Starting point:** branch from the default integration branch after fetch + pull.
3. **Checkout** the branch before implementation.
4. **Push** to `origin` (or configured remote) so CI can see it.
5. **One issue per branch** when scopes diverge.

If the key is missing for ticketed work, ask before naming the branch.

## Commits

- Commit when the user asks or when completing a logical unit of git-owned work
  after edits exist.
- Prefer Conventional Commits or existing project style; **include the issue key**
  when ticketed (e.g. `HOME-123: short description`).
- Prefer small commits; squash only when requested or when cleaning a noisy WIP
  branch for PR.

## Remotes

- **Same-repo (default):** branch on canonical repo, push `origin`, open PR via
  **`github`** specialist.
- **Fork:** push to fork and PR upstream when the user uses that model.

## Conflicts

- Report conflicts clearly; resolve in the working tree here (**`code`**) unless
  unsafe without context.

## Coordination with `github`

Typical sequence: **`jira`** (context) → **`code`** (branch, implement, commit,
push) → **`github`** (PR, checks, Actions). See
[../github/03-responsibility-split.md](../github/03-responsibility-split.md).
