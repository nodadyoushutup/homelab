# Epic Issue Type

Use these instructions for `Epic` issues in the `Homelab` / `HOME` Jira
project.

## Field Metadata

- No existing `Epic` issues were returned by the available `HOME` Jira sample
  queries.
- The available MCP tools did not expose create-screen metadata for `Epic`.
- No `Epic`-specific custom fields are confirmed for `HOME` from the current
  metadata.

## Required Fields

- Required by the Jira MCP create contract: `project_key`, `summary`,
  `issue_type`.
- Use `project_key: "HOME"` and `issue_type: "Epic"` unless the user explicitly
  overrides the project.
- No additional required `Epic` custom fields are currently documented for
  `HOME`.

## Operating Instructions

- Create an `Epic` only when the user explicitly asks for an epic or the work is
  clearly a large parent initiative.
- Do not ask for custom field values before creating an `Epic` unless Jira
  rejects the create call with a specific required-field error.
- If Jira reports a required field during creation, capture the field id, field
  name, expected value shape, and update this instruction file.
