# Subtask Issue Type

Use these instructions for `Subtask` issues in the `Homelab` / `HOME` Jira
project.

## Field Metadata

Sampled `HOME` Subtask issues returned the following custom fields:

- `customfield_10000`: `Development`; observed value shape `{ "value": "{}" }`.
- `customfield_10001`: `Team`; observed as null.
- `customfield_10015`: `Start date`; observed as null.
- `customfield_10017`: `Issue color`; observed as null.
- `customfield_10019`: `Rank`; observed as a Jira Software rank string.
- `customfield_10021`: `Flagged`; observed as null.
- `customfield_10031`: `Design`; observed as null.
- `customfield_10103`: `Requirements`; project-scoped paragraph field used to
  store the specific parent requirement this subtask implements.
- `customfield_10104`: `Acceptance Criteria`; project-scoped paragraph field
  used to store the matching acceptance criterion for this subtask.

No `Subtask`-specific custom field was confirmed as required by the available
MCP metadata.

## Required Fields

- Required by the Jira MCP create contract: `project_key`, `summary`,
  `issue_type`.
- Operationally required for subtasks: `parent`.
- Use `project_key: "HOME"` and `issue_type: "Subtask"` unless the user
  explicitly overrides the project.
- No additional required `Subtask` custom fields are currently documented for
  `HOME`.

## Operating Instructions

- Use `Subtask` only as child work under an existing `Story`, `Bug`, or `Task`.
- Never create a top-level `Subtask`; identify the parent issue key first.
- When generated from a parent requirement, name the subtask exactly after the
  requirement, preserving the `REQ-###` prefix.
- When generated from a parent requirement, copy that one requirement into the
  subtask's `Requirements` field (`customfield_10103`).
- When generated from a parent requirement, copy the matching `AC-###`
  acceptance criterion into the subtask's `Acceptance Criteria` field
  (`customfield_10104`).
- Keep generated requirement subtask descriptions short. A single sentence that
  explains the subtask exists to satisfy the referenced requirement is enough.
- When executing work, treat each requirement subtask as a checklist item.
  Transition it to `Done` only after the corresponding requirement work is
  actually complete.
- Put the parent issue key in `additional_fields` using Jira's expected parent
  shape when creating the subtask.
- Do not manually set `Rank`, `Development`, `Design`, or `Issue color` during
  normal subtask creation; those are Jira/Jira Software managed fields unless
  live metadata proves otherwise.
- If Jira reports a required field during creation, capture the field id, field
  name, expected value shape, and update this instruction file.
