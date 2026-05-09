# Bug Issue Type

Use these instructions for `Bug` issues in the `Homelab` / `HOME` Jira project.

## Field Metadata

- No existing `Bug` issues were returned by the available `HOME` Jira sample
  queries.
- The available MCP tools did not expose create-screen metadata for `Bug`.
- `customfield_10103`: `Requirements`; project-scoped paragraph field used to
  store locked `REQ-###` requirements during `REQUIREMENTS`.
- `customfield_10104`: `Acceptance Criteria`; project-scoped paragraph field
  used to store locked `AC-###` acceptance criteria during `REQUIREMENTS`.
- `customfield_10105`: `Workflow Impact`; project-scoped paragraph field used
  during `TECH LEAD`.
- `customfield_10106`: `Technical Notes`; project-scoped paragraph field used
  during `TECH LEAD`.

## Required Fields

- Required by the Jira MCP create contract: `project_key`, `summary`,
  `issue_type`.
- Use `project_key: "HOME"` and `issue_type: "Bug"` unless the user explicitly
  overrides the project.
- No additional required `Bug` custom fields are currently documented for
  `HOME`.
- Before leaving `REQUIREMENTS`, `customfield_10103` must be populated with the
  locked bug requirements.
- Before leaving `REQUIREMENTS`, `customfield_10104` must be populated with one
  acceptance criterion for every bug requirement.
- Before leaving `REQUIREMENTS`, each bug requirement must have a matching child
  `Subtask`.
- Before leaving `TECH LEAD`, `customfield_10105` and `customfield_10106` must
  be populated.
- Before leaving `DEVELOPMENT`, a GitHub pull request must be submitted for the
  bug work.
- After code review passes, the bug should move to `DEPLOY` by default unless
  the user asks to test first.
- After deploy is complete, transition the bug to `DONE`.

## Operating Instructions

- Prefer `Bug` when something is broken and needs fixing.
- Do not ask for custom field values before creating a `Bug` unless Jira
  rejects the create call with a specific required-field error.
- In `REQUIREMENTS`, write the bug requirements to `customfield_10103` as a
  Markdown unordered list using `REQ-###` prefixes.
- After bug requirements are complete, generate matching acceptance criteria in
  `customfield_10104` using `AC-###` prefixes unless the user explicitly wants
  to provide them.
- Create one child `Subtask` per bug requirement, using the requirement name as
  the subtask summary.
- In `TECH LEAD`, return the locked Jira context so the supervisor can route
  technical soundness, workflow impact, and code impact review to the Tech Lead
  specialist.
- In `TECH LEAD`, store workflow impact in `customfield_10105` and senior
  developer guidance in `customfield_10106`.
- When `TECH LEAD` is complete, transition the bug to `DEVELOPMENT`.
- In `DEVELOPMENT`, return the locked Jira context so the supervisor can route
  implementation to the Code specialist.
- When the Code specialist submits a GitHub pull request, transition the bug to
  `CODE REVIEW`.
- If code review fails, transition the bug back to `DEVELOPMENT` for another
  implementation pass.
- If code review passes, transition the bug to `DEPLOY` by default.
- If the user asks to test the approved pull request first, route through `TEST`
  before `DEPLOY` when Jira exposes that transition.
- After deploy is complete, transition the bug to `DONE`.
- If Jira reports a required field during creation, capture the field id, field
  name, expected value shape, and update this instruction file.
