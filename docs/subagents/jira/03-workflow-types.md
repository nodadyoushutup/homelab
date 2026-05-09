# Jira Workflow Types

## Bug-Specific Rules

- Treat `Bug` as the issue type for something broken that needs fixing.
- In `TO DO`, guide the user toward a brief high-level summary rather than a
  fully detailed specification.
- In `REQUIREMENTS`, gather and lock the issue requirements in the
  `Requirements` custom field (`customfield_10103`).
- Format requirements as a Markdown unordered list, ordered sensibly for the
  work, with each item prefixed by `REQ-###`, such as `REQ-001`.
- After requirements are complete, generate matching acceptance criteria in the
  `Acceptance Criteria` custom field (`customfield_10104`) unless the user
  explicitly wants to provide them.
- Create one child `Subtask` for each requirement, using the requirement name as
  the subtask summary.
- When requirements, acceptance criteria, and requirement subtasks are complete,
  transition the main `Bug` issue from `REQUIREMENTS` to `TECH LEAD`.
- In `REPLICATE`, either add a comment with replicate results or add a comment
  explaining that replication was intentionally skipped.
- In `TECH LEAD`, return the locked Jira context so the supervisor can route
  technical soundness review, code impact analysis, and workflow impact analysis
  to the Tech Lead specialist.
- In `TECH LEAD`, write workflow impact to `Workflow Impact`
  (`customfield_10105`) and developer guidance to `Technical Notes`
  (`customfield_10106`).
- If `TECH LEAD` finds serious issues with the `Bug` requirements or acceptance
  criteria, add a Jira comment with reasons and suggestions, then transition the
  main `Bug` issue back to `REQUIREMENTS`.
- When `TECH LEAD` is complete, transition the main `Bug` issue to
  `DEVELOPMENT`.
- In `DEVELOPMENT`, return the locked Jira context so the supervisor can route
  implementation to the `Code` specialist.
- When the Code specialist submits a GitHub pull request, transition the main
  `Bug` issue to `CODE REVIEW`.
- If code review fails, transition the main `Bug` issue back to `DEVELOPMENT`
  for another implementation pass.
- If code review passes, transition the main `Bug` issue to `DEPLOY` by default.
- If the user asks to test first, route through `TEST` before `DEPLOY` when Jira
  exposes that transition.
- After deploy is complete, transition the main `Bug` issue to `DONE`.
- During execution, use requirement subtasks as the working checklist and mark
  each subtask `Done` only when its requirement is completed.
- Preserve the team's current fast-path behavior: it is acceptable for
  implementation to commit directly to `main` and then move the Jira status
  through downstream stages as a lightweight workflow formality.

## Story-Specific Rules

- Treat `Story` as the issue type for new features, improvements, and general
  code changes that are not bug fixes.
- Treat `Story` as the default issue type for new Jira issue requests when the
  user does not explicitly specify an issue type.
- In `TO DO`, guide the user toward a brief high-level summary rather than a
  fully detailed specification.
- In `TO DO`, create a useful baseline description from the user's overview.
  Make it clearer and more complete than a rough prompt, but do not expand it
  into full requirements yet.
- In `REQUIREMENTS`, gather and lock the issue requirements in the
  `Requirements` custom field (`customfield_10103`).
- Format requirements as a Markdown unordered list, ordered sensibly for the
  work, with each item prefixed by `REQ-###`, such as `REQ-001`.
- After requirements are complete, generate matching acceptance criteria in the
  `Acceptance Criteria` custom field (`customfield_10104`) unless the user
  explicitly wants to provide them.
- Create one child `Subtask` for each requirement, using the requirement name as
  the subtask summary.
- When requirements, acceptance criteria, and requirement subtasks are complete,
  transition the main `Story` issue from `REQUIREMENTS` to `TECH LEAD`.
- In `TECH LEAD`, return the locked Jira context so the supervisor can route
  technical soundness review, code impact analysis, and workflow impact analysis
  to the Tech Lead specialist.
- In `TECH LEAD`, write workflow impact to `Workflow Impact`
  (`customfield_10105`) and developer guidance to `Technical Notes`
  (`customfield_10106`).
- If `TECH LEAD` finds serious issues with the `Story` requirements or
  acceptance criteria, add a Jira comment with reasons and suggestions, then
  transition the main `Story` issue back to `REQUIREMENTS`.
- When `TECH LEAD` is complete, transition the main `Story` issue to
  `DEVELOPMENT`.
- In `DEVELOPMENT`, return the locked Jira context so the supervisor can route
  implementation to the `Code` specialist.
- When the Code specialist submits a GitHub pull request, transition the main
  `Story` issue to `CODE REVIEW`.
- If code review fails, transition the main `Story` issue back to `DEVELOPMENT`
  for another implementation pass.
- If code review passes, transition the main `Story` issue to `DEPLOY` by
  default.
- If the user asks to test first, route through `TEST` before `DEPLOY` when Jira
  exposes that transition.
- After deploy is complete, transition the main `Story` issue to `DONE`.
- During execution, use requirement subtasks as the working checklist and mark
  each subtask `Done` only when its requirement is completed.
- Treat the `Story` lifecycle as the same as the `Bug` lifecycle except that
  `Story` does not include the `REPLICATE` stage.
- Preserve the team's current fast-path behavior: it is acceptable for
  implementation to commit directly to `main` and then move the Jira status
  through downstream stages as a lightweight workflow formality.

## Task-Specific Rules

- Treat `Task` as using the same front-end capture model as `Story` and `Bug`
  for `TO DO` and `REQUIREMENTS`.
- In `TO DO`, guide the user toward a brief high-level summary rather than a
  fully detailed specification.
- In `REQUIREMENTS`, gather and lock the issue requirements in the
  `Requirements` custom field (`customfield_10103`).
- Format requirements as a Markdown unordered list, ordered sensibly for the
  work, with each item prefixed by `REQ-###`, such as `REQ-001`.
- After requirements are complete, generate matching acceptance criteria in the
  `Acceptance Criteria` custom field (`customfield_10104`) unless the user
  explicitly wants to provide them.
- Create one child `Subtask` for each requirement, using the requirement name as
  the subtask summary.
- When requirements, acceptance criteria, and requirement subtasks are complete,
  transition the main `Task` issue from `REQUIREMENTS` to `TECH LEAD` when the
  task is receiving technical review.
- Treat `Task` as intentionally simpler after requirements are captured: once
  the work is performed, it can move directly to `DONE`.
- If a `Task` goes through `TECH LEAD`, transition it to `DEVELOPMENT` when
  technical review is complete.
- If `TECH LEAD` finds serious issues with the `Task` requirements or acceptance
  criteria, add a Jira comment with reasons and suggestions, then transition the
  main `Task` issue back to `REQUIREMENTS`.
- If a `Task` has a GitHub pull request, transition it from `DEVELOPMENT` to
  `CODE REVIEW` when that pull request is submitted.
- If code review fails for a `Task`, transition it back to `DEVELOPMENT` for
  another implementation pass.
- If code review passes for a `Task`, transition it to `DEPLOY` by default.
- If the user asks to test first, route through `TEST` before `DEPLOY` when Jira
  exposes that transition.
- After deploy is complete, transition the main `Task` issue to `DONE`.
- During execution, use requirement subtasks as the working checklist and mark
  each subtask `Done` only when its requirement is completed.
- Allow `Task` for code work only when the user explicitly wants a lighter
  quick-task path instead of the fuller `Story` or `Bug` lifecycle.

## Subtask-Specific Rules

- Treat `Subtask` as a minimal child-work item under a parent `Task`, `Story`,
  or `Bug`.
- `Subtask` is effectively "did it" or "did not do it": use `TO DO`, `DONE`,
  and `CANCELED`.
- Do not force a separate requirements-expansion phase onto `Subtask` unless
  the user explicitly wants more detail.
- Treat `Subtask` as an absolute rarity unless the user explicitly directs it
  or the amount of work clearly benefits from child checklist tracking.
