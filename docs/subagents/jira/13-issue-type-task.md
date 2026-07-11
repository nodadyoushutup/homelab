# Task Issue Type (homelab)

Use for **`Task`** on **`HOME`**. Lighter path and optional tech review:
**`03-workflow-types.md`**.

## Field metadata

- Same **`10103`–`10106`** roles as **`Story`** when those stages apply.

## Gates (HOME)

- **`REQUIREMENTS`** exit: same **`10103` / `10104` / subtasks** as **`Story`** when
  the task goes through full requirements.
- If **`TECH LEAD`** applies, populate **`10105` / `10106`** before leaving that stage.
- If code work + PR: **`DEVELOPMENT` → `CODE REVIEW` → …** as in **`02-issue-flows.md`**.
- Prefer **`Task`** for simple or operational work; use for code only when the user
  wants a lighter path than **`Story`** / **`Bug`**.
