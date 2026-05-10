# GitHub pull request policies

Policies for the **Git** specialist when using the **GitHub MCP**. Tool names
and capabilities depend on the deployed `mcp-github` server; stay within what
the tools expose and report gaps instead of guessing APIs.

## Principles

1. **Read before write:** Summarize open PRs, diffs, checks, or review state with
   read-oriented tools before requesting reviews, merging, or changing PR
   metadata.
2. **Least privilege:** Do not perform destructive or irreversible actions
   (merge, delete branch, dismiss reviews) unless the user explicitly asked for
   that outcome.
3. **Traceability:** PR **title or description** should reference the **Jira
   issue key** when work is ticketed (e.g. `HOME-123: …`), matching the git
   branch policy.

## Opening and updating PRs

- **Base branch:** Default to the repository’s primary integration branch
  (`main` or team default) unless the user names another target.
- **Draft vs ready:**
  - Use **draft** for WIP or when checks are expected to fail initially.
  - Mark **ready for review** when the user asks and checks are green or
    failures are acknowledged.
- **Description:** Include purpose, scope, testing notes, and linked issue key.
  Avoid pasting secrets or tokens.

## Reviews and assignments

- **Request reviewers** when the user names them or when repo convention lists
  owners; otherwise suggest who should review and return control to the
  supervisor.
- **Re-request review** after substantial pushes only when appropriate; mention
  what changed.

## Checks and automation

- **Read check / workflow status** before claiming a PR is mergeable.
- **Re-run failed workflows** only when the user asks and the GitHub MCP exposes
  that capability; otherwise describe the failure and recommend manual re-run in
  the GitHub UI.
- Treat **required status checks** and **branch protection** as hard gates: if
  merge is blocked, report the reason rather than attempting unsafe overrides.

## Merge strategy

- Prefer **squash** or **merge** per project convention; if unknown, **ask** or
  choose the least destructive default documented in the repo.
- **Do not merge** with failing required checks unless the user explicitly
  overrides and understands the policy exception.

## After merge

- Recommend **deleting the remote feature branch** when the user wants a tidy
  remote and the repo allows it.
- Recommend **`jira`** for transition to “Done” / deployment columns when that
  matches the team workflow.

## Responsibility split

| Request | Owner |
| --- | --- |
| PR open/update/merge, checks, review requests | `git` (GitHub MCP) |
| File content, tests, local conflict resolution | `code` |
| Issue status, comments on ticket | `jira` |
| Architecture sign-off before large change | `tech_lead` (then `git` for PR) |
