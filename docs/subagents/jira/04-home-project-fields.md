# HOME Project Fields

These instructions are based on live Jira metadata gathered through the
Atlassian MCP tools for the `HOME` project.

## Default Project And Board

- The default Jira project is `Homelab` with project key `HOME`.
- The Jira board returned for `HOME` is `DRIFT board` with board id `36`.
- Treat `Homelab` / `HOME` as the default and fallback project and
  `DRIFT board` as the default and fallback board when the user does not name a
  different Jira project or board.
- If the user explicitly names a different project or board, honor that request
  for the current task.

## Custom Fields Observed

The following custom fields were returned by Jira field metadata and observed on
`HOME` issue payloads where sample issues existed:

- `customfield_10000`: `Development`; Jira development integration summary
  field, schema type `any`.
- `customfield_10001`: `Team`; Atlassian team field, schema type `team`.
- `customfield_10015`: `Start date`; date picker, schema type `date`.
- `customfield_10017`: `Issue color`; Jira Software issue color, schema type
  `string`.
- `customfield_10019`: `Rank`; Jira Software rank field, schema type `any`.
- `customfield_10021`: `Flagged`; checkbox field, schema type `array` of
  options.
- `customfield_10031`: `Design`; Jira design integration field, schema type
  `array`.
- `customfield_10103`: `Requirements`; project-scoped paragraph field for
  `HOME`, schema type `string`, Jira custom type `textarea`.
- `customfield_10104`: `Acceptance Criteria`; project-scoped paragraph field
  for `HOME`, schema type `string`, Jira custom type `textarea`.
- `customfield_10105`: `Workflow Impact`; project-scoped paragraph field for
  `HOME`, schema type `string`, Jira custom type `textarea`.
- `customfield_10106`: `Technical Notes`; project-scoped paragraph field for
  `HOME`, schema type `string`, Jira custom type `textarea`.

`customfield_10030` (`Vulnerability`) appears in Jira global field metadata, but
it was not observed on the sampled `HOME` issues returned by the available MCP
queries.

## Required Field Metadata

- The Jira MCP create contract requires `project_key`, `summary`, and
  `issue_type` for all issue creation calls.
- For `Subtask`, `parent` is operationally required because a subtask must be
  created under an existing parent issue.
- The available MCP tools did not expose project create-screen metadata showing
  additional per-issue-type required custom fields for `HOME`.
- Do not invent required custom fields. If Jira rejects a create or update due
  to a missing required field, treat that live error as source-of-truth metadata
  and update these instructions.

## Mutation Guidance

- Do not set integration-managed fields such as `Development`, `Design`,
  `Rank`, `Issue color`, or `Vulnerability` unless the user explicitly asks and
  Jira metadata confirms the field is writable for the action.
- Prefer leaving optional custom fields unset during initial issue creation.
- Use `customfield_10103` (`Requirements`) during the `REQUIREMENTS` stage for
  `Story`, `Bug`, and `Task` issues.
- Use `customfield_10103` (`Requirements`) on generated requirement subtasks to
  store the single parent requirement that subtask implements.
- Store requirements in `customfield_10103` as a Markdown unordered list, with
  each item prefixed by a stable `REQ-###` identifier such as `REQ-001`.
- Use `customfield_10104` (`Acceptance Criteria`) during the `REQUIREMENTS`
  stage for `Story`, `Bug`, and `Task` issues after requirements are complete.
- Use `customfield_10104` (`Acceptance Criteria`) on generated requirement
  subtasks to store the matching acceptance criterion for that subtask.
- Store acceptance criteria in `customfield_10104` as a Markdown unordered list,
  with each item prefixed by a stable `AC-###` identifier whose number maps to
  the matching requirement, such as `AC-001` for `REQ-001`.
- Use `customfield_10105` (`Workflow Impact`) during the `TECH LEAD` stage for
  `Story` and `Bug` issues, and for `Task` issues that receive a technical
  review.
- Use `customfield_10106` (`Technical Notes`) during the `TECH LEAD` stage for
  `Story` and `Bug` issues, and for `Task` issues that receive a technical
  review.
- When custom field values are needed, use Jira field IDs in `additional_fields`
  and preserve the value shape required by Jira.
