# Development Stage

These instructions describe the `DEVELOPMENT` flow now that the runtime has a
concrete Code specialist for implementation work.

## Code Agent Handoff

- When a Jira issue enters `DEVELOPMENT` or the user asks to execute code work
  for a Jira issue, return a compact handoff package so the supervisor can route
  the implementation request to `code`.
- The Jira result returned to the supervisor should include the issue context
  the Code specialist needs before starting: description, requirements,
  acceptance criteria, technical notes, workflow impact, comments, subtasks,
  issue type, and current status.
- The Code specialist owns determining the actual implementation approach. Jira
  instructions should not over-prescribe the code changes because the work may
  involve many different kinds of systems, files, tools, or operational tasks.
- The expected Code specialist behavior is to identify the relevant code areas,
  perform code analysis, make the required changes, validate them, and prepare
  the work for review.

## Subtask Progress

- Use requirement subtasks as the working checklist during development.
- As each requirement is completed, transition the matching child `Subtask` to
  `Done`.
- If a requirement cannot be completed, leave the matching subtask open and
  record or report the blocker.
- If the user asks to complete only a specific requirement, work only the
  matching `REQ-###` subtask unless broader changes are required to make that
  requirement valid.

## Pull Request Handoff

- Development is complete when the Code specialist has finished the applicable
  work and submitted a GitHub pull request.
- Once a GitHub pull request has been submitted for the Jira issue, transition
  the main issue from `DEVELOPMENT` to `CODE REVIEW`.
- Include the pull request URL in the Jira update or summary when available.
- If Jira does not expose a direct `CODE REVIEW` transition, inspect live
  transitions and report the blocker instead of pretending the handoff happened.

## Failed Review Loop

- If code review fails, the supervisor should route the resulting Jira update so
  the main issue moves from `CODE REVIEW` back to `DEVELOPMENT`.
- The return to `DEVELOPMENT` means the Code specialist should take another pass
  using the review feedback and remaining open work.
- Do not mark the parent issue complete just because a pull request exists; the
  pull request moves the issue into review, not to done.
