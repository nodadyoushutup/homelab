# Task Issue Type

Use these instructions for `Task` issues in the `Homelab` / `HOME` Jira project.

## Field Metadata

- No existing `Task` issues were returned by the available `HOME` Jira sample
  queries.
- The available MCP tools did not expose create-screen metadata for `Task`.
- `customfield_10103`: `Requirements`; project-scoped paragraph field used to
  store locked `REQ-###` requirements during `REQUIREMENTS`.
- `customfield_10104`: `Acceptance Criteria`; project-scoped paragraph field
  used to store locked `AC-###` acceptance criteria during `REQUIREMENTS`.
- `customfield_10105`: `Workflow Impact`; project-scoped paragraph field used
  when a `Task` receives technical review.
- `customfield_10106`: `Technical Notes`; project-scoped paragraph field used
  when a `Task` receives technical review.

## Required Fields

- Required by the Jira MCP create contract: `project_key`, `summary`,
  `issue_type`.
- Use `project_key: "HOME"` and `issue_type: "Task"` unless the user explicitly
  overrides the project.
- No additional required `Task` custom fields are currently documented for
  `HOME`.
- Before leaving `REQUIREMENTS`, `customfield_10103` must be populated with the
  locked task requirements.
- Before leaving `REQUIREMENTS`, `customfield_10104` must be populated with one
  acceptance criterion for every task requirement.
- Before leaving `REQUIREMENTS`, each task requirement must have a matching child
  `Subtask`.
- If a `Task` goes through technical review, populate `customfield_10105` and
  `customfield_10106` before leaving that review.
- If a `Task` goes through `DEVELOPMENT` for code work, a GitHub pull request
  must be submitted before moving it to `CODE REVIEW`.
- After code review passes, a code-work task should move to `DEPLOY` by default
  unless the user asks to test first.
- After deploy is complete, transition the task to `DONE`.

## Operating Instructions

- Prefer `Task` for simple one-off work, chores, or operational follow-up.
- For code work, use `Task` only when the user explicitly wants a lighter
  quick-task path instead of the fuller `Story` or `Bug` lifecycle.
- Do not ask for custom field values before creating a `Task` unless Jira
  rejects the create call with a specific required-field error.
- In `REQUIREMENTS`, write the task requirements to `customfield_10103` as a
  Markdown unordered list using `REQ-###` prefixes.
- After task requirements are complete, generate matching acceptance criteria in
  `customfield_10104` using `AC-###` prefixes unless the user explicitly wants
  to provide them.
- Create one child `Subtask` per task requirement, using the requirement name as
  the subtask summary.
- If a `Task` needs technical review, return the locked Jira context so the
  supervisor can route technical soundness, workflow impact, and code impact
  review to the Tech Lead specialist.
- During `Task` technical review, store workflow impact in `customfield_10105`
  and senior developer guidance in `customfield_10106`.
- If technical review is complete for a `Task`, transition it to `DEVELOPMENT`.
- In `DEVELOPMENT`, return the locked Jira context so the supervisor can route
  implementation to the Code specialist when code work is required.
- When the Code specialist submits a GitHub pull request, transition the task to
  `CODE REVIEW`.
- If code review fails, transition the task back to `DEVELOPMENT` for another
  implementation pass.
- If code review passes, transition the task to `DEPLOY` by default.
- If the user asks to test the approved pull request first, route through `TEST`
  before `DEPLOY` when Jira exposes that transition.
- After deploy is complete, transition the task to `DONE`.
- If Jira reports a required field during creation, capture the field id, field
  name, expected value shape, and update this instruction file.
