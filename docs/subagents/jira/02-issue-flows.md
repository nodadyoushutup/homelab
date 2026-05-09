# Jira Issue Flows

## Intent Rules

- Treat language such as "create", "open", "file", "log", "raise", "submit",
  "add", "make", or "write up" a Jira issue, ticket, task, story, bug, or epic
  as net-new issue intent when there is no existing issue key in scope.
- Prefer net-new issue handling when the main outcome is a brand new Jira issue
  and there is no existing issue key to modify.
- Treat requests that mention an existing issue key or ask to change current
  Jira work as existing issue updates unless the user is also clearly asking to
  open a separate new issue.

## New Issue Flow

- Start every net-new issue request as a backlog `TO DO` ticket.
- Default to issue type `Story` when the user asks for a new Jira issue and does
  not specify an issue type.
- Use another issue type only when the user specifies it or uses unmistakable
  type language such as `epic`, `bug`, `task`, or `subtask`.
- Treat `Subtask` as a rare child-work issue under an existing `Story`, `Bug`,
  or `Task`, not as a normal top-level issue choice.
- If the user supplied the issue type, preserve it unless Jira rejects that type
  for the target project.
- If the user did not supply enough information to understand what the ticket is
  for, ask for a brief overview before creating the issue.
- Accept either brief or verbose intake details. Do not require a fully scoped
  specification during initial creation.
- Generate a concise plain-language summary from the user's overview when the
  user does not provide a clean summary.
- Write a useful baseline Jira description even when the user's first prompt is
  short or rough. The description should be more complete than the raw prompt,
  but still lightweight: capture the idea, intent, and any specifics already
  provided without inventing detailed requirements.
- Treat initial creation as getting the idea onto the vision board and into the
  backlog. Full scoping happens later in `REQUIREMENTS`.
- If the user does not name a project or board, use the `Homelab` project with
  key `HOME` as the default and fallback instead of asking for one unless Jira
  blocks that choice.
- If the user names a different Jira project or board, honor that explicit
  override for the request instead of forcing the `Homelab` / `HOME` default.
- For a new `Bug`, create the issue in `TO DO` with a short baseline summary
  and useful baseline description first, then use later workflow stages to
  expand the description and planning details.
- For a new `Story`, create the issue in `TO DO` with a short baseline summary
  and useful baseline description first, then use later workflow stages to
  expand the description and planning details.
- For a new `Task`, create the issue in `TO DO` with a short baseline summary
  and useful baseline description first, then use later workflow stages only
  when needed.

## Post-Creation Start Flow

- After creating a new backlog `TO DO` issue, ask whether the user wants to move
  it onto the active board and start working on it now.
- Do not ask that follow-up when the original request already says, in any
  natural language, that the user wants to start now, work on it now, scope it
  now, move it forward now, put it on the active board, or otherwise begin the
  workflow immediately.
- When immediate-start intent is present, create the issue first, then move it
  out of backlog onto the active board using the available Jira workflow action,
  then transition it to `REQUIREMENTS`.
- For `Story`, `Bug`, and `Task`, `REQUIREMENTS` is the normal first active
  working status after backlog `TO DO`.
- If Jira does not expose a direct active-board or `REQUIREMENTS` transition,
  inspect the live transitions and take the closest valid transition that starts
  requirements work. If no valid transition exists, report the blocker instead
  of inventing a state change.
- When moving an issue out of backlog, keep the transition call minimal. Some
  Jira transition-comment fields expect Atlassian Document Format; if a note is
  needed, transition first and add a separate Jira comment instead of sending a
  plain-text transition comment.

## Existing Issue Flow

- For existing issues, keep the requested change mapped cleanly to supported
  edit surfaces before mutation.
- Handle comments, assignments, field edits, and transitions directly in this
  agent.
- Gather missing workflow or transition context from Jira before acting when
  needed.
- Do not allow an issue to leave `REQUIREMENTS` until all required Jira fields
  are populated and a hard verification check confirms they are filled.
- When a `Story`, `Bug`, or `Task` completes `REQUIREMENTS`, transition the main
  issue to `TECH LEAD`; this is the handoff onto the tech lead's plate.
- When `TECH LEAD` finds serious issues with requirements or acceptance
  criteria, transition the main issue back to `REQUIREMENTS` and add a Jira
  comment with the reasons, rejected ideas, and suggestions for rework.
- When `TECH LEAD` completes successfully, transition the main issue to
  `DEVELOPMENT`; this is the point where the supervisor can route the locked
  Jira context to the Code specialist.
- When development produces a submitted GitHub pull request, transition the main
  issue from `DEVELOPMENT` to `CODE REVIEW`.
- When code review fails, transition the main issue from `CODE REVIEW` back to
  `DEVELOPMENT` for another implementation pass.
- When code review passes or the pull request is approved, transition the main
  issue from `CODE REVIEW` to `DEPLOY` by default.
- If the user asks to test an approved pull request before deploy, use the
  available test workflow first, then transition to `DEPLOY`.
- After deployment is complete, transition the main issue from `DEPLOY` to
  `DONE`.
- After substantive Jira work, summarize the current stage, what changed, and
  the next stage you recommend.
