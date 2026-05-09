# Story Issue Type

Use these instructions for `Story` issues in the `Homelab` / `HOME` Jira
project.

## Field Metadata

Sampled `HOME` Story issues returned the following custom fields:

- `customfield_10000`: `Development`; observed value shape `{ "value": "{}" }`.
- `customfield_10001`: `Team`; observed as null.
- `customfield_10015`: `Start date`; observed as null.
- `customfield_10017`: `Issue color`; observed as null.
- `customfield_10019`: `Rank`; observed as a Jira Software rank string.
- `customfield_10021`: `Flagged`; observed as null.
- `customfield_10031`: `Design`; observed as null.
- `customfield_10103`: `Requirements`; project-scoped paragraph field used to
  store locked `REQ-###` requirements during `REQUIREMENTS`.
- `customfield_10104`: `Acceptance Criteria`; project-scoped paragraph field
  used to store locked `AC-###` acceptance criteria during `REQUIREMENTS`.
- `customfield_10105`: `Workflow Impact`; project-scoped paragraph field used
  during `TECH LEAD`.
- `customfield_10106`: `Technical Notes`; project-scoped paragraph field used
  during `TECH LEAD`.

No `Story`-specific custom field was confirmed as required by the available MCP
metadata.

## Required Fields

- Required by the Jira MCP create contract: `project_key`, `summary`,
  `issue_type`.
- Use `project_key: "HOME"` and `issue_type: "Story"` unless the user
  explicitly overrides the project.
- No additional required `Story` custom fields are currently documented for
  `HOME`.
- Before leaving `REQUIREMENTS`, `customfield_10103` must be populated with the
  locked story requirements.
- Before leaving `REQUIREMENTS`, `customfield_10104` must be populated with one
  acceptance criterion for every story requirement.
- Before leaving `REQUIREMENTS`, each story requirement must have a matching
  child `Subtask`.
- Before leaving `TECH LEAD`, `customfield_10105` and `customfield_10106` must
  be populated.
- Before leaving `DEVELOPMENT`, a GitHub pull request must be submitted for the
  story work.
- After code review passes, the story should move to `DEPLOY` by default unless
  the user asks to test first.
- After deploy is complete, transition the story to `DONE`.

## Operating Instructions

- Prefer `Story` for new features, improvements, and general code changes that
  are not bug fixes.
- Use `Story` as the default issue type for net-new Jira issue requests when the
  user does not explicitly specify another type.
- During initial creation, only require enough overview information to create a
  sensible backlog `TO DO` ticket.
- If the user gives a rough or brief prompt, write a clean baseline description
  that captures the idea, intent, and provided specifics without inventing a
  fully scoped plan.
- Do not set optional custom fields during initial `Story` creation unless the
  user asks for a specific value or Jira requires it.
- Do not manually set `Rank`, `Development`, `Design`, or `Issue color` during
  normal story creation; those are Jira/Jira Software managed fields unless live
  metadata proves otherwise.
- In `REQUIREMENTS`, write the story requirements to `customfield_10103` as a
  Markdown unordered list using `REQ-###` prefixes.
- After story requirements are complete, generate matching acceptance criteria
  in `customfield_10104` using `AC-###` prefixes unless the user explicitly wants
  to provide them.
- Create one child `Subtask` per story requirement, using the requirement name as
  the subtask summary.
- In `TECH LEAD`, return the locked Jira context so the supervisor can route
  technical soundness, workflow impact, and code impact review to the Tech Lead
  specialist.
- In `TECH LEAD`, store workflow impact in `customfield_10105` and senior
  developer guidance in `customfield_10106`.
- When `TECH LEAD` is complete, transition the story to `DEVELOPMENT`.
- In `DEVELOPMENT`, return the locked Jira context so the supervisor can route
  implementation to the Code specialist.
- When the Code specialist submits a GitHub pull request, transition the story
  to `CODE REVIEW`.
- If code review fails, transition the story back to `DEVELOPMENT` for another
  implementation pass.
- If code review passes, transition the story to `DEPLOY` by default.
- If the user asks to test the approved pull request first, route through `TEST`
  before `DEPLOY` when Jira exposes that transition.
- After deploy is complete, transition the story to `DONE`.
- If Jira reports a required field during creation, capture the field id, field
  name, expected value shape, and update this instruction file.
