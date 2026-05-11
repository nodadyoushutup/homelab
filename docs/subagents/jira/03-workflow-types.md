# Jira Workflow Types (homelab)

Full lifecycles for **`Story`**, **`Bug`**, **`Task`**, **`Subtask`**, and
**`Epic`** on **`HOME`** are split across this file (differences only),
**`02-issue-flows.md`** (shared transitions), **`04-home-project-fields.md`**
(fields), **`05`–`09`** (stages), and **`10`–`14`** (per-type metadata and gates).

## Bug-specific

- **`Bug`:** something broken; includes **`REPLICATE`** (comment with results or
  intentional skip) before or as part of the bug flow per live Jira—see
  **`12-issue-type-bug.md`**.
- Otherwise follows the same **`REQUIREMENTS` → `TECH LEAD` → `DEVELOPMENT` → …**
  pattern as **`Story`** in **`02-issue-flows.md`**.

## Story-specific

- Default net-new type when unspecified (**`11-issue-type-story.md`**).
- No **`REPLICATE`** stage (unlike **`Bug`**).

## Task-specific

- Lighter path: may skip much of post-requirements flow when the user chose a
  quick task (**`13-issue-type-task.md`**).
- If **`TECH LEAD`** applies, then **`DEVELOPMENT`** / PR / review / deploy as for
  **`Story`** when code work is involved.

## Subtask-specific

- Child under **`Story`**, **`Bug`**, or **`Task`** only; minimal lifecycle
  (**`14-issue-type-subtask.md`**). Used heavily as the requirement checklist
  (**`05-requirements-stage.md`**).

## Epic-specific

- Only when the user asks or scope is clearly a large parent initiative
  (**`10-issue-type-epic.md`**).
